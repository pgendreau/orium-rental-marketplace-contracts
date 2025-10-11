// SPDX-License-Identifier: CC0-1.0

pragma solidity 0.8.9;

import { OwnableUpgradeable } from '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import { Initializable } from '@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol';
import { PausableUpgradeable } from '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import { IERC1155 } from '@openzeppelin/contracts/token/ERC1155/IERC1155.sol';
import { IERC7589 } from './interfaces/IERC7589.sol';
import { IERC7589Legacy } from './interfaces/IERC7589Legacy.sol';
import { LibOriumSftMarketplace, RentalOffer, CommitAndGrantRoleParams } from './libraries/LibOriumSftMarketplace.sol';
import { IOriumMarketplaceRoyalties } from './interfaces/IOriumMarketplaceRoyalties.sol';

/**
 * @title Orium Marketplace - Marketplace for renting SFTs
 * @dev This contract is used to manage SFTs rentals, powered by ERC-7589 Semi-Fungible Token Roles
 * @author Orium Network Team - developers@orium.network
 */
contract OriumSftMarketplace is Initializable, OwnableUpgradeable, PausableUpgradeable {
    /** ######### Global Variables ########### **/

    /// @dev oriumMarketplaceRoyalties stores the collection royalties and fees
    address public oriumMarketplaceRoyalties;

    /// @dev Aavegotchi Wearable address (legacy, only valid on Polygon)
    address constant aavegotchiWearableAddress = 0x052e6c114a166B0e91C2340370d72D4C33752B4b;

    /// @dev hashedOffer => bool
    mapping(bytes32 => bool) public isCreated;

    /// @dev lender => nonce => deadline
    mapping(address => mapping(uint256 => uint64)) public nonceDeadline;

    /// @dev rolesRegistry => commitmentId => nonce
    mapping(address => mapping(uint256 => uint256)) public commitmentIdToNonce;

    /// @dev hashedOffer => Rental
    mapping(bytes32 => Rental) public rentals;

    /** ######### Structs ########### **/

    /// @dev Rental info.
    struct Rental {
        address borrower;
        uint64 expirationDate;
    }

    /** ######### Events ########### **/

    /**
     * @param nonce The nonce of the rental offer
     * @param tokenAddress The address of the contract of the SFT to rent
     * @param tokenId The tokenId of the SFT to rent
     * @param tokenAmount The amount of SFT to rent
     * @param commitmentId The commitmentId of the SFT to rent
     * @param lender The address of the user lending the SFT
     * @param borrower The address of the user renting the SFT
     * @param feeTokenAddress The address of the ERC20 token for rental fees
     * @param feeAmountPerSecond The amount of fee per second
     * @param deadline The deadline until when the rental offer is valid
     * @param minDuration The minimum duration of the rental
     * @param roles The array of roles to be assigned to the borrower
     * @param rolesData The array of data for each role
     */
    event RentalOfferCreated(
        uint256 indexed nonce,
        address indexed tokenAddress,
        uint256 indexed tokenId,
        uint256 tokenAmount,
        uint256 commitmentId,
        address lender,
        address borrower,
        address feeTokenAddress,
        uint256 feeAmountPerSecond,
        uint256 deadline,
        uint64 minDuration,
        bytes32[] roles,
        bytes[] rolesData
    );

    /**
     * @param lender The address of the lender
     * @param nonce The nonce of the rental offer
     * @param borrower The address of the borrower
     * @param expirationDate The expiration date of the rental
     */
    event RentalStarted(address indexed lender, uint256 indexed nonce, address indexed borrower, uint64 expirationDate);

    /**
     * @param lender The address of the lender
     * @param nonce The nonce of the rental offer
     */
    event RentalOfferCancelled(address indexed lender, uint256 indexed nonce);

    /**
     * @param lender The address of the lender
     * @param nonce The nonce of the rental offer
     */
    event RentalEnded(address indexed lender, uint256 indexed nonce);

    /** ######### Modifiers ########### **/

    /** ######### Initializer ########### **/
    /**
     * @notice Initializes the contract.
     * @dev The owner of the contract will be the owner of the protocol.
     * @param _owner The owner of the protocol.
     * @param _oriumMarketplaceRoyalties The address of the OriumMarketplaceRoyalties contract.
     */
    function initialize(address _owner, address _oriumMarketplaceRoyalties) public initializer {
        __Pausable_init();
        __Ownable_init();

        oriumMarketplaceRoyalties = _oriumMarketplaceRoyalties;

        transferOwnership(_owner);
    }

    /** ============================ Rental Functions  ================================== **/

    /**
     * @notice Creates a batch of rental offers.
     * @param _offers The array of rental offer structs.
     */
    function batchCreateRentalOffer(RentalOffer[] memory _offers) external whenNotPaused {
      for (uint256 i = 0; i < _offers.length; i++) {
        createRentalOffer(_offers[i]);
      }
    }

    /** ######### Setters ########### **/
    /**
     * @notice Creates a rental offer.
     * @dev To optimize for gas, only the offer hash is stored on-chain
     * @param _offer The rental offer struct.
     */
    function createRentalOffer(RentalOffer memory _offer) public whenNotPaused {
        address _rolesRegistryAddress = IOriumMarketplaceRoyalties(oriumMarketplaceRoyalties).sftRolesRegistryOf(
            _offer.tokenAddress
        );
        _validateCreateRentalOffer(_offer, _rolesRegistryAddress);

        if (_offer.commitmentId == 0) {
            _offer.commitmentId = _commitOrLockTokens(
                _offer.tokenAddress,
                _rolesRegistryAddress,
                _offer.lender,
                _offer.tokenId,
                _offer.tokenAmount
            );
        }

        nonceDeadline[msg.sender][_offer.nonce] = _offer.deadline;
        isCreated[LibOriumSftMarketplace.hashRentalOffer(_offer)] = true;
        commitmentIdToNonce[_rolesRegistryAddress][_offer.commitmentId] = _offer.nonce;

        emit RentalOfferCreated(
            _offer.nonce,
            _offer.tokenAddress,
            _offer.tokenId,
            _offer.tokenAmount,
            _offer.commitmentId,
            _offer.lender,
            _offer.borrower,
            _offer.feeTokenAddress,
            _offer.feeAmountPerSecond,
            _offer.deadline,
            _offer.minDuration,
            _offer.roles,
            _offer.rolesData
        );
    }

    /**
     * @notice Accepts a batch of rental offers.
     * @param _offers The array of rental offers struct. It should be the same as the ones used to create the offer.
     * @param _durations The duration of the rental.
     */
    // function batchAcceptRentalOffer(
    //     RentalOffer[] calldata _offers,
    //     uint64[] calldata _durations
    // ) external payable whenNotPaused {
    //   require(_offers.length == _durations.length, 'Arrays must be the same length');
    //   for (uint256 i = 0; i < _offers.length; i++) {
    //     acceptRentalOffer(_offers[i], _durations[i]);
    //   }
    // }

    /**
     * @notice Accepts a rental offer.
     * @dev The borrower can be address(0) to allow anyone to rent the SFT.
     * @param _offer The rental offer struct. It should be the same as the one used to create the offer.
     * @param _duration The duration of the rental.
     */
    function acceptRentalOffer(
        RentalOffer calldata _offer,
        uint64 _duration
    ) public payable whenNotPaused {
        bytes32 _offerHash = LibOriumSftMarketplace.hashRentalOffer(_offer);
        uint64 _expirationDate = uint64(block.timestamp + _duration);
        LibOriumSftMarketplace.validateAcceptRentalOffer(
            _offer.borrower,
            _offer.minDuration,
            isCreated[_offerHash],
            rentals[_offerHash].expirationDate,
            _duration,
            nonceDeadline[_offer.lender][_offer.nonce],
            _expirationDate
        );

        IERC7589 _rolesRegistry = IERC7589(
            IOriumMarketplaceRoyalties(oriumMarketplaceRoyalties).sftRolesRegistryOf(_offer.tokenAddress)
        );
        for (uint256 i = 0; i < _offer.roles.length; i++) {
            _rolesRegistry.grantRole(
                _offer.commitmentId,
                _offer.roles[i],
                msg.sender,
                _expirationDate,
                false,
                _offer.rolesData[i]
            );
        }

        rentals[_offerHash] = Rental({ borrower: msg.sender, expirationDate: _expirationDate });
        _transferFees(_offer.tokenAddress, _offer.feeTokenAddress, _offer.feeAmountPerSecond, _duration, _offer.lender);

        emit RentalStarted(_offer.lender, _offer.nonce, msg.sender, _expirationDate);
    }

    /**
     * @notice Delist a batch of rental offers.
     * @param _offers The array of rental offer structs. It should be the same as the ones used to create the offer.
     */
    function batchDelistRentalOffer(RentalOffer[] calldata _offers) external whenNotPaused {
      for (uint256 i = 0; i < _offers.length; i++) {
        delistRentalOffer(_offers[i]);
      }
    }

    /**
     * @notice Delist a rental offer.
     * @param _offer The rental offer struct. It should be the same as the one used to create the offer.
     */
    function delistRentalOffer(RentalOffer calldata _offer) public whenNotPaused {
        _delistRentalOffer(_offer);
    }

    /**
     * @notice Delist a rental offer and withdraw it.
     * @param _offer The rental offer struct. It should be the same as the one used to create the offer.
     */
    function delistRentalOfferAndWithdraw(RentalOffer calldata _offer) external whenNotPaused {
        _delistRentalOffer(_offer);

        if (_offer.tokenAddress == aavegotchiWearableAddress) {
            IERC7589Legacy _rolesRegistryLegacy = IERC7589Legacy(
                IOriumMarketplaceRoyalties(oriumMarketplaceRoyalties).sftRolesRegistryOf(_offer.tokenAddress)
            );
            _rolesRegistryLegacy.releaseTokens(_offer.commitmentId);
        } else {
            IERC7589 _rolesRegistry = IERC7589(
                IOriumMarketplaceRoyalties(oriumMarketplaceRoyalties).sftRolesRegistryOf(_offer.tokenAddress)
            );
            _rolesRegistry.unlockTokens(_offer.commitmentId);
        }
    }

    /**
     * @notice Ends the rental prematurely.
     * @dev Can only be called by the borrower.
     * @dev Borrower needs to approve marketplace to revoke the roles.
     * @param _offer The rental offer struct. It should be the same as the one used to create the offer.
     */
    function endRental(RentalOffer calldata _offer) external whenNotPaused {
        bytes32 _offerHash = LibOriumSftMarketplace.hashRentalOffer(_offer);

        require(isCreated[_offerHash], 'Offer not created');
        require(msg.sender == rentals[_offerHash].borrower, 'Only borrower can end a rental');
        require(
            rentals[_offerHash].expirationDate > block.timestamp,
            'There are no active Rentals'
        );

        IERC7589 _rolesRegistry = IERC7589(
            IOriumMarketplaceRoyalties(oriumMarketplaceRoyalties).sftRolesRegistryOf(_offer.tokenAddress)
        );
        address _borrower = rentals[_offerHash].borrower;

        for (uint256 i = 0; i < _offer.roles.length; i++) {
            _rolesRegistry.revokeRole(_offer.commitmentId, _offer.roles[i], _borrower);
        }

        rentals[_offerHash].expirationDate = uint64(block.timestamp);

        emit RentalEnded(_offer.lender, _offer.nonce);
    }

    /**
     * @notice Releases the tokens in the commitment batch.
     * @dev Can only be called by the commitment's grantor.
     * @param _tokenAddresses The SFT tokenAddresses.
     * @param _commitmentIds The commitmentIds to release.
     */
    function batchReleaseTokens(
        address[] calldata _tokenAddresses,
        uint256[] calldata _commitmentIds
    ) external whenNotPaused {
        LibOriumSftMarketplace.batchReleaseTokens(oriumMarketplaceRoyalties, _tokenAddresses, _commitmentIds);
    }

    /**
     * @notice batchCommitTokensAndGrantRole commits tokens and grant role in a single transaction.
     * @param _params The array of CommitAndGrantRoleParams.
     */
    function batchCommitTokensAndGrantRole(CommitAndGrantRoleParams[] calldata _params) external whenNotPaused {
        for (uint256 i = 0; i < _params.length; i++) {
            address _rolesRegistryAddress = IOriumMarketplaceRoyalties(oriumMarketplaceRoyalties).sftRolesRegistryOf(
                _params[i].tokenAddress
            );

            uint256 _validCommitmentId = _params[i].commitmentId;
            if (_params[i].commitmentId == 0) {
                _validCommitmentId = _commitOrLockTokens(
                    _params[i].tokenAddress,
                    _rolesRegistryAddress,
                    msg.sender,
                    _params[i].tokenId,
                    _params[i].tokenAmount
                );
            } else {
                // if the user provided a valid commitmentId, it's necessary to verify if they actually own it,
                // and if all other parameters passed match the commitmentId
                LibOriumSftMarketplace.validateCommitmentId(
                    _params[i].commitmentId,
                    _params[i].tokenAddress,
                    _params[i].tokenId,
                    _params[i].tokenAmount,
                    msg.sender,
                    _rolesRegistryAddress
                );
            }

            IERC7589(_rolesRegistryAddress).grantRole(
                _validCommitmentId,
                _params[i].role,
                _params[i].grantee,
                _params[i].expirationDate,
                _params[i].revocable,
                _params[i].data
            );
        }
    }

    /**
     * @notice batchRevokeRole revokes role in a single transaction.
     * @dev grantor will be msg.sender and it must approve the marketplace to revoke the roles.
     * @param _commitmentIds The array of commitmentIds
     * @param _roles The array of roles
     * @param _grantees The array of grantees
     * @param _tokenAddresses The array of tokenAddresses
     */
    function batchRevokeRole(
        uint256[] memory _commitmentIds,
        bytes32[] memory _roles,
        address[] memory _grantees,
        address[] memory _tokenAddresses
    ) external whenNotPaused {
        LibOriumSftMarketplace.batchRevokeRole(
            _commitmentIds,
            _roles,
            _grantees,
            _tokenAddresses,
            oriumMarketplaceRoyalties
        );
    }

    /** ######### Internals ########### **/

    /**
     * @dev Validates if is wearable address to use commit or lock functions.
     * @param _tokenAddress The SFT tokenAddresses.
     * @param _rolesRegistryAddress roles registry address.
     * @param _lender The address of the user lending the SFT.
     * @param _tokenId The tokenId of the SFT to rent.
     * @param _tokenAmount The amount of SFT to rent.
     */
    function _commitOrLockTokens(
        address _tokenAddress,
        address _rolesRegistryAddress,
        address _lender,
        uint256 _tokenId,
        uint256 _tokenAmount
    ) internal returns (uint256) {
        if (_tokenAddress == aavegotchiWearableAddress) {
            return IERC7589Legacy(_rolesRegistryAddress).commitTokens(_lender, _tokenAddress, _tokenId, _tokenAmount);
        } else {
            return IERC7589(_rolesRegistryAddress).lockTokens(_lender, _tokenAddress, _tokenId, _tokenAmount);
        }
    }

    /**
     * @dev Validates the create rental offer.
     * @param _offer The rental offer struct.
     */
    function _validateCreateRentalOffer(RentalOffer memory _offer, address _rolesRegistryAddress) internal view {
        require(
            IOriumMarketplaceRoyalties(oriumMarketplaceRoyalties).isTrustedFeeTokenAddressForToken(
                _offer.tokenAddress,
                _offer.feeTokenAddress
            ),
            'tokenAddress is not trusted'
        );
        require(
            _offer.deadline <= block.timestamp + IOriumMarketplaceRoyalties(oriumMarketplaceRoyalties).maxDuration() &&
                _offer.deadline > block.timestamp,
            'Invalid deadline'
        );
        LibOriumSftMarketplace.validateOffer(_offer);
        require(nonceDeadline[_offer.lender][_offer.nonce] == 0, 'nonce already used');

        if (_offer.commitmentId != 0) {
            uint256 _commitmentNonce = commitmentIdToNonce[_rolesRegistryAddress][_offer.commitmentId];

            if (_commitmentNonce != 0) {
                require(
                    nonceDeadline[_offer.lender][_commitmentNonce] < block.timestamp,
                    'commitmentId is in an active rental offer'
                );
            }

            LibOriumSftMarketplace.validateCommitmentId(
                _offer.commitmentId,
                _offer.tokenAddress,
                _offer.tokenId,
                _offer.tokenAmount,
                _offer.lender,
                _rolesRegistryAddress
            );
        } else {
            require(
                IERC1155(_offer.tokenAddress).balanceOf(msg.sender, _offer.tokenId) >= _offer.tokenAmount,
                'caller does not have enough balance for the token'
            );
        }
    }

    /**
     * @dev Transfers the fees to the marketplace, the creator and the lender.
     * @param _feeTokenAddress The address of the ERC20 token for rental fees.
     * @param _feeAmountPerSecond  The amount of fee per second.
     * @param _duration The duration of the rental.
     * @param _lenderAddress The address of the lender.
     */
    function _transferFees(
        address _tokenAddress,
        address _feeTokenAddress,
        uint256 _feeAmountPerSecond,
        uint64 _duration,
        address _lenderAddress
    ) internal {
        uint256 _feeAmount = _feeAmountPerSecond * _duration;
        if (_feeAmount == 0) return;

        uint256 _marketplaceFeeAmount = LibOriumSftMarketplace.getAmountFromPercentage(
            _feeAmount,
            IOriumMarketplaceRoyalties(oriumMarketplaceRoyalties).marketplaceFeeOf(_tokenAddress)
        );
        IOriumMarketplaceRoyalties.RoyaltyInfo memory _royaltyInfo = IOriumMarketplaceRoyalties(
            oriumMarketplaceRoyalties
        ).royaltyInfoOf(_tokenAddress);

        uint256 _royaltyAmount = LibOriumSftMarketplace.getAmountFromPercentage(
            _feeAmount,
            _royaltyInfo.royaltyPercentageInWei
        );
        uint256 _lenderAmount = _feeAmount - _royaltyAmount - _marketplaceFeeAmount;

        if (_feeTokenAddress == address(0)) {
            require(msg.value == _feeAmount, 'Insufficient native token amount');
            payable(owner()).transfer(_marketplaceFeeAmount);
            payable(_royaltyInfo.treasury).transfer(_royaltyAmount);
            payable(_lenderAddress).transfer(_lenderAmount);
        } else {
            LibOriumSftMarketplace.transferFees(
                _feeTokenAddress,
                _marketplaceFeeAmount,
                _royaltyAmount,
                _lenderAmount,
                owner(),
                _royaltyInfo.treasury,
                _lenderAddress
            );
        }
    }

    /**
     * @dev Cancels a rental offer.
     * @param _offer The rental offer struct.
     */
    function _delistRentalOffer(RentalOffer calldata _offer) internal {
        bytes32 _offerHash = LibOriumSftMarketplace.hashRentalOffer(_offer);
        require(isCreated[_offerHash], 'Offer not created');
        require(msg.sender == _offer.lender, 'Only lender can cancel a rental offer');
        require(
            nonceDeadline[_offer.lender][_offer.nonce] > block.timestamp,
            'Nonce expired or not used yet'
        );
        nonceDeadline[msg.sender][_offer.nonce] = uint64(block.timestamp);
        emit RentalOfferCancelled(_offer.lender, _offer.nonce);
    }

    /** ============================ Core Functions  ================================== **/

    /** ######### Setters ########### **/

    /**
     * @notice Pauses the contract.
     * @dev Only owner can pause the contract.
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     * @dev Only owner can unpause the contract.
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets the address of the OriumMarketplaceRoyalties contract.
     * @dev Only owner can set the address of the OriumMarketplaceRoyalties contract.s
     * @param _oriumMarketplaceRoyalties The address of the OriumMarketplaceRoyalties contract.
     */
    function setOriumMarketplaceRoyalties(address _oriumMarketplaceRoyalties) external onlyOwner {
        oriumMarketplaceRoyalties = _oriumMarketplaceRoyalties;
    }

    /** ######### Getters ########### **/
}
