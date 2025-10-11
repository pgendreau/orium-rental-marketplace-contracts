// SPDX-License-Identifier: CC0-1.0

pragma solidity 0.8.9;

import { IERC7589 } from '../interfaces/IERC7589.sol';
import { IERC7589Legacy } from '../interfaces/IERC7589Legacy.sol';
import { IOriumMarketplaceRoyalties } from '../interfaces/IOriumMarketplaceRoyalties.sol';
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/// @dev Rental offer info.
struct RentalOffer {
    address lender;
    address borrower;
    address tokenAddress;
    uint256 tokenId;
    uint256 tokenAmount;
    address feeTokenAddress;
    uint256 feeAmountPerSecond;
    uint256 nonce;
    uint256 commitmentId;
    uint64 deadline;
    uint64 minDuration;
    bytes32[] roles;
    bytes[] rolesData;
}

struct CommitAndGrantRoleParams {
    uint256 commitmentId;
    address tokenAddress;
    uint256 tokenId;
    uint256 tokenAmount;
    bytes32 role;
    address grantee;
    uint64 expirationDate;
    bool revocable;
    bytes data;
}

library LibOriumSftMarketplace {
    /// @dev 100 ether is 100%
    uint256 public constant MAX_PERCENTAGE = 100 ether;

    /// @dev 2.5 ether is 2.5%
    uint256 public constant DEFAULT_FEE_PERCENTAGE = 2.5 ether;

    /// @dev Aavegotchi Wearable address (legacy, only valid on Polygon)
    address public constant aavegotchiWearableAddress = 0x052e6c114a166B0e91C2340370d72D4C33752B4b;

    /**
     * @notice Gets the rental offer hash.
     * @dev This function is used to hash the rental offer struct with retrocompatibility.
     * is only used for reading the hash from the storage.
     * @param _offer The rental offer struct to be hashed.
     */
    function hashRentalOffer(RentalOffer memory _offer) external pure returns (bytes32) {
        return
            _offer.minDuration == 0
                ? keccak256(
                    abi.encode(
                        _offer.lender,
                        _offer.borrower,
                        _offer.tokenAddress,
                        _offer.tokenId,
                        _offer.tokenAmount,
                        _offer.feeTokenAddress,
                        _offer.feeAmountPerSecond,
                        _offer.nonce,
                        _offer.commitmentId,
                        _offer.deadline,
                        _offer.roles,
                        _offer.rolesData
                    )
                )
                : keccak256(abi.encode(_offer));
    }

    /**
     * @dev All values needs to be in wei.
     * @param _amount The amount to calculate the percentage from.
     * @param _percentage The percentage to calculate.
     */
    function getAmountFromPercentage(uint256 _amount, uint256 _percentage) external pure returns (uint256) {
        return (_amount * _percentage) / MAX_PERCENTAGE;
    }

    /**
     * @notice Validates the commitmentId.
     * @param _commitmentId The commitmentId to validate.
     * @param _tokenAddress The token address.
     * @param _tokenId The token id.
     * @param _tokenAmount The token amount.
     * @param _expectedGrantor The expected grantor.
     * @param _rolesRegistryAddress The roles registry address.
     */
    function validateCommitmentId(
        uint256 _commitmentId,
        address _tokenAddress,
        uint256 _tokenId,
        uint256 _tokenAmount,
        address _expectedGrantor,
        address _rolesRegistryAddress
    ) external view {
        if (_tokenAddress == aavegotchiWearableAddress) {
            IERC7589Legacy _rolesRegistryLegacy = IERC7589Legacy(_rolesRegistryAddress);
            require(
                _rolesRegistryLegacy.grantorOf(_commitmentId) == _expectedGrantor,
                'OriumSftMarketplace: expected grantor does not match the grantor of the commitmentId'
            );
            require(
                _rolesRegistryLegacy.tokenAmountOf(_commitmentId) == _tokenAmount,
                "OriumSftMarketplace: tokenAmount provided does not match commitment's tokenAmount"
            );
            require(
                _rolesRegistryLegacy.tokenIdOf(_commitmentId) == _tokenId,
                "OriumSftMarketplace: tokenId provided does not match commitment's tokenId"
            );
        } else {
            IERC7589 _rolesRegistry = IERC7589(_rolesRegistryAddress);
            require(
                _rolesRegistry.tokenAmountOf(_commitmentId) == _tokenAmount,
                "OriumSftMarketplace: tokenAmount provided does not match commitment's tokenAmount"
            );
            require(
                _rolesRegistry.ownerOf(_commitmentId) == _expectedGrantor,
                'OriumSftMarketplace: expected grantor does not match the grantor of the commitmentId'
            );
            require(
                _rolesRegistry.tokenAddressOf(_commitmentId) == _tokenAddress,
                "OriumSftMarketplace: tokenAddress provided does not match commitment's tokenAddress"
            );
            require(
                _rolesRegistry.tokenIdOf(_commitmentId) == _tokenId,
                "OriumSftMarketplace: tokenId provided does not match commitment's tokenId"
            );
        }
    }

    /**
     * @notice Validates the rental offer.
     * @param _offer The rental offer struct to be validated.
     */
    function validateOffer(RentalOffer memory _offer) external view {
        require(_offer.tokenAmount > 0, 'OriumSftMarketplace: tokenAmount should be greater than 0');
        require(_offer.nonce != 0, 'OriumSftMarketplace: Nonce cannot be 0');
        require(msg.sender == _offer.lender, 'OriumSftMarketplace: Sender and Lender mismatch');
        require(_offer.roles.length > 0, 'OriumSftMarketplace: roles should not be empty');
        require(
            _offer.roles.length == _offer.rolesData.length,
            'OriumSftMarketplace: roles and rolesData should have the same length'
        );
        require(
            _offer.borrower != address(0) || _offer.feeAmountPerSecond > 0,
            'OriumSftMarketplace: feeAmountPerSecond should be greater than 0'
        );
        require(_offer.minDuration <= _offer.deadline - block.timestamp, 'OriumSftMarketplace: minDuration is invalid');
    }

    /**
     * @notice Transfers the fees.
     * @dev The fee token address should be approved before calling this function.
     * @param _feeTokenAddress The fee token address.
     * @param _marketplaceFeeAmount The marketplace fee amount.
     * @param _royaltyAmount The royalty amount.
     * @param _lenderAmount The lender amount.
     * @param _marketplaceTreasuryAddress The marketplace treasury address.
     * @param _royaltyTreasuryAddress The royalty treasury address.
     * @param _lenderAddress The lender address.
     */
    function transferFees(
        address _feeTokenAddress,
        uint256 _marketplaceFeeAmount,
        uint256 _royaltyAmount,
        uint256 _lenderAmount,
        address _marketplaceTreasuryAddress,
        address _royaltyTreasuryAddress,
        address _lenderAddress
    ) external {
        if (_marketplaceFeeAmount > 0) {
            require(
                IERC20(_feeTokenAddress).transferFrom(msg.sender, _marketplaceTreasuryAddress, _marketplaceFeeAmount),
                'OriumSftMarketplace: Transfer failed'
            );
        }

        if (_royaltyAmount > 0) {
            require(
                IERC20(_feeTokenAddress).transferFrom(msg.sender, _royaltyTreasuryAddress, _royaltyAmount),
                'OriumSftMarketplace: Transfer failed'
            );
        }

        require(
            IERC20(_feeTokenAddress).transferFrom(msg.sender, _lenderAddress, _lenderAmount),
            'OriumSftMarketplace: Transfer failed'
        );
    }

    /**
     * @notice Releases the tokens in the commitment batch.
     * @dev Can only be called by the commitment's grantor.
     * @param _oriumMarketplaceRoyaltiesAddress The address of the OriumMarketplaceRoyalties contract.
     * @param _tokenAddresses The SFT tokenAddresses.
     * @param _commitmentIds The commitmentIds to release.
     */
    function batchReleaseTokens(
        address _oriumMarketplaceRoyaltiesAddress,
        address[] calldata _tokenAddresses,
        uint256[] calldata _commitmentIds
    ) external {
        require(_tokenAddresses.length == _commitmentIds.length, 'OriumSftMarketplace: arrays length mismatch');
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            address _rolesRegistryAddress = IOriumMarketplaceRoyalties(_oriumMarketplaceRoyaltiesAddress)
                .sftRolesRegistryOf(_tokenAddresses[i]);

            if (_tokenAddresses[i] == aavegotchiWearableAddress) {
                require(
                    IERC7589Legacy(_rolesRegistryAddress).grantorOf(_commitmentIds[i]) == msg.sender,
                    "OriumSftMarketplace: sender is not the commitment's grantor Legacy"
                );
                IERC7589Legacy(_rolesRegistryAddress).releaseTokens(_commitmentIds[i]);
            } else {
                require(
                    IERC7589(_rolesRegistryAddress).ownerOf(_commitmentIds[i]) == msg.sender,
                    "OriumSftMarketplace: sender is not the commitment's grantor"
                );
                require(
                    IERC7589(_rolesRegistryAddress).tokenAddressOf(_commitmentIds[i]) == _tokenAddresses[i],
                    "OriumSftMarketplace: tokenAddress provided does not match commitment's tokenAddress"
                );
                IERC7589(_rolesRegistryAddress).unlockTokens(_commitmentIds[i]);
            }
        }
    }

    /**
     * @notice batchRevokeRole revokes role in a single transaction.
     * @dev only the grantor and grantee can call this function. Be careful as the marketplace have approvals from other users.
     * @param _commitmentIds The array of commitmentIds
     * @param _roles The array of roles
     * @param _grantees The array of grantees
     * @param _tokenAddresses The array of tokenAddresses
     */
    function batchRevokeRole(
        uint256[] memory _commitmentIds,
        bytes32[] memory _roles,
        address[] memory _grantees,
        address[] memory _tokenAddresses,
        address _oriumMarketplaceRoyalties
    ) external {
        require(
            _commitmentIds.length == _roles.length &&
                _commitmentIds.length == _grantees.length &&
                _commitmentIds.length == _tokenAddresses.length,
            'OriumSftMarketplace: arrays length mismatch'
        );

        for (uint256 i = 0; i < _commitmentIds.length; i++) {
            address _rolesRegistryAddress = IOriumMarketplaceRoyalties(_oriumMarketplaceRoyalties).sftRolesRegistryOf(
                _tokenAddresses[i]
            );

            if (_tokenAddresses[i] == aavegotchiWearableAddress) {
                require(
                    msg.sender == _grantees[i] ||
                        IERC7589Legacy(_rolesRegistryAddress).grantorOf(_commitmentIds[i]) == msg.sender,
                    "OriumSftMarketplace: sender is not the commitment's grantor or grantee Legacy"
                );
                require(
                    IERC7589Legacy(_rolesRegistryAddress).roleExpirationDate(
                        _commitmentIds[i],
                        _roles[i],
                        _grantees[i]
                    ) > block.timestamp,
                    'OriumSftMarketplace: role is expired'
                );
                require(
                    IERC7589Legacy(_rolesRegistryAddress).isRoleRevocable(_commitmentIds[i], _roles[i], _grantees[i]),
                    'OriumSftMarketplace: role is not revocable Legacy'
                );
            } else {
                require(
                    msg.sender == _grantees[i] ||
                        IERC7589(_rolesRegistryAddress).ownerOf(_commitmentIds[i]) == msg.sender,
                    "OriumSftMarketplace: sender is not the commitment's grantor or grantee"
                );
                require(
                    IERC7589(_rolesRegistryAddress).roleExpirationDate(_commitmentIds[i], _roles[i]) > block.timestamp,
                    'OriumSftMarketplace: role is expired'
                );
                require(
                    IERC7589(_rolesRegistryAddress).isRoleRevocable(_commitmentIds[i], _roles[i]),
                    'OriumSftMarketplace: role is not revocable'
                );
                require(
                    IERC7589(_rolesRegistryAddress).tokenAddressOf(_commitmentIds[i]) == _tokenAddresses[i],
                    "OriumSftMarketplace: tokenAddress provided does not match commitment's tokenAddress"
                );
            }
            IERC7589(_rolesRegistryAddress).revokeRole(_commitmentIds[i], _roles[i], _grantees[i]);
        }
    }

    function validateAcceptRentalOffer(
        address _borrower,
        uint64 _minDuration,
        bool _isCreated,
        uint64 _previousRentalExpirationDate,
        uint64 _duration,
        uint256 _nonceDeadline,
        uint64 _expirationDate
    ) external view {
        require(_isCreated, 'OriumSftMarketplace: Offer not created');
        require(
            _previousRentalExpirationDate <= block.timestamp,
            'OriumSftMarketplace: This offer has an ongoing rental'
        );
        require(_duration >= _minDuration, 'OriumSftMarketplace: Duration is less than the offer minimum duration');
        require(
            _nonceDeadline > _expirationDate,
            'OriumSftMarketplace: expiration date is greater than offer deadline'
        );
        require(
            address(0) == _borrower || msg.sender == _borrower,
            'OriumSftMarketplace: Sender is not allowed to rent this SFT'
        );
    }
}
