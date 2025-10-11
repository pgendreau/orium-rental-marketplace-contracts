import hre, { ethers, network, upgrades } from 'hardhat'
import { confirmOrDie, print, colors } from '../../utils/misc'
import { updateJsonFile } from '../../utils/json'
import addresses, { Network } from '../../addresses'
import { provider, deployer } from '../../utils/deployer'

const NETWORK = network.name as Network
const { Multisig, OriumMarketplaceRoyalties } = addresses[NETWORK]

const CONTRACT_NAME = 'OriumSftMarketplace'
const OPERATOR_ADDRESS = "0x5DaFd030C07844741157CcDcc366306822dd5FF3"
const INITIALIZER_ARGUMENTS: string[] = [OPERATOR_ADDRESS, OriumMarketplaceRoyalties.address]

const networkConfig: any = network.config
/* const FEE_DATA: any = {
  maxFeePerGas: ethers.utils.parseUnits('80', 'gwei'),
  maxPriorityFeePerGas: ethers.utils.parseUnits('50', 'gwei'),
}
provider.getFeeData = async () => FEE_DATA */

async function main() {
  const deployerAddress = await deployer.getAddress()
  confirmOrDie(`Deploying ${CONTRACT_NAME} contract on: ${NETWORK} network with ${deployerAddress}. Continue?`)

  const LibraryFactory = await ethers.getContractFactory('LibOriumSftMarketplace', deployer)
  const library = await LibraryFactory.deploy()
  await library.waitForDeployment()

  const ContractFactory = await ethers.getContractFactory(CONTRACT_NAME, {
    signer: deployer,
    libraries: {
      LibOriumSftMarketplace: await library.getAddress(),
    },
  })
  const contract = await upgrades.deployProxy(ContractFactory, INITIALIZER_ARGUMENTS, {
    unsafeAllowLinkedLibraries: true,
  })
  await contract.waitForDeployment()
  const contractAddress = await contract.getAddress()
  print(colors.success, `${CONTRACT_NAME} deployed to: ${contractAddress}`)

  print(colors.highlight, 'Updating config files...')
  const deploymentInfo = {
    [CONTRACT_NAME]: {
      address: contractAddress,
      operator: OPERATOR_ADDRESS,
      implementation: await upgrades.erc1967.getImplementationAddress(contractAddress),
      proxyAdmin: await upgrades.erc1967.getAdminAddress(contractAddress),
    },
  }

  console.log(deploymentInfo)

  updateJsonFile(`addresses/${NETWORK}/index.json`, deploymentInfo)

  print(colors.success, 'Config files updated!')

  try {
    print(colors.highlight, 'Transferring proxy admin ownership...')
    const abi = [
      {
        inputs: [
          {
            internalType: 'address',
            name: 'newOwner',
            type: 'address',
          },
        ],
        name: 'transferOwnership',
        outputs: [],
        stateMutability: 'nonpayable',
        type: 'function',
      },
    ]
    const proxyAdminContract = new ethers.Contract(deploymentInfo[CONTRACT_NAME].proxyAdmin, abi, deployer)
    await proxyAdminContract.transferOwnership(OPERATOR_ADDRESS)
    print(colors.success, `Proxy admin ownership transferred to: ${OPERATOR_ADDRESS}`)
  } catch (e) {
    print(colors.error, `Error transferring proxy admin ownership: ${e}`)
  }

  print(colors.highlight, 'Verifying contract on Etherscan...')
  await hre.run('verify:verify', {
    address: contractAddress,
    constructorArguments: [],
  })
  print(colors.success, 'Contract verified!')
}

main()
  .then(async () => {
    print(colors.bigSuccess, 'All done!')
  })
  .catch(error => {
    console.error(error)
    process.exitCode = 1
  })
