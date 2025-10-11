import hre, { ethers, network, upgrades } from 'hardhat'
import { print, confirmOrDie, colors } from './misc'
import addresses, { Network } from '../addresses'
import { updateJsonFile } from './json'
import { provider, deployer } from './deployer'

const NETWORK = network.name as Network

/**
 * @notice Upgrade an proxy contract
 * @dev The contract must existis in a solidity file in the contracts folder with the same name
 * @param PROXY_CONTRACT_NAME The name of the contract
 * @param LIBRARIES_CONTRACT_NAME The name of the libraries
 * @param CUSTOM_FEE_DATA The custom fee data
 */
export async function upgradeProxy(
  PROXY_CONTRACT_NAME: keyof (typeof addresses)[Network],
  LIBRARIES_CONTRACT_NAME?: string[],
  CUSTOM_FEE_DATA?: { maxFeePerGas: bigint; maxPriorityFeePerGas: bigint },
) {
  if (CUSTOM_FEE_DATA !== undefined) {
    const FEE_DATA: any = CUSTOM_FEE_DATA
    provider.getFeeData = async () => FEE_DATA
  }
  const deployerAddress = await deployer.getAddress()
  const libraries: { [key: string]: string } = {}

  await confirmOrDie(
    `Upgrading ${PROXY_CONTRACT_NAME} contract on: ${NETWORK} network with ${deployerAddress}. Continue?`,
  )

  if (LIBRARIES_CONTRACT_NAME !== undefined) {
    print(colors.highlight, 'Deploying libraries...')

    for (const LIBRARY_CONTRACT_NAME of LIBRARIES_CONTRACT_NAME) {
      const LibraryFactory = await ethers.getContractFactory(LIBRARY_CONTRACT_NAME, deployer)
      const library = await LibraryFactory.deploy()
      await library.waitForDeployment()
      libraries[LIBRARY_CONTRACT_NAME] = await library.getAddress()
    }

    print(colors.success, 'Libraries deployed!')
  }

  print(colors.highlight, 'Upgrading proxy contract...')
  const ContractFactory = await ethers.getContractFactory(PROXY_CONTRACT_NAME, {
    libraries,
    signer: deployer,
  })
  const contract = await upgrades.upgradeProxy(addresses[NETWORK][PROXY_CONTRACT_NAME].address, ContractFactory, {
    unsafeAllowLinkedLibraries: true,
  })
  await contract.waitForDeployment()
  print(colors.success, `${PROXY_CONTRACT_NAME} upgraded to: ${contract.getAddress()}`)

  print(colors.highlight, 'Updating config files...')
  const deploymentInfo: any = {
    [PROXY_CONTRACT_NAME]: {
      ...addresses[NETWORK][PROXY_CONTRACT_NAME],
      implementation: await upgrades.erc1967.getImplementationAddress(await contract.getAddress()),
    },
  }

  if (LIBRARIES_CONTRACT_NAME) {
    deploymentInfo[PROXY_CONTRACT_NAME].libraries = libraries
  }

  console.log(deploymentInfo)
  updateJsonFile(`addresses/${NETWORK}/index.json`, deploymentInfo)
  print(colors.success, 'Config files updated!')

  if (LIBRARIES_CONTRACT_NAME) {
    print(colors.highlight, 'Verifying libraries on block explorer...')
    for (const LIBRARY_CONTRACT_NAME of LIBRARIES_CONTRACT_NAME) {
      try {
        print(colors.highlight, `Verifying library ${LIBRARY_CONTRACT_NAME}...`)
        await hre.run('verify:verify', {
          address: libraries[LIBRARY_CONTRACT_NAME],
          constructorArguments: [],
        })
        print(colors.success, `${LIBRARY_CONTRACT_NAME} verified!`)
      } catch (e) {
        print(colors.error, `Error verifying library ${LIBRARY_CONTRACT_NAME}: ${e}`)
      }
    }
  }

  print(colors.highlight, 'Verifying contract on block explorer...')
  await hre.run('verify:verify', {
    address: await contract.getAddress(),
    constructorArguments: [],
  })
  print(colors.success, `${PROXY_CONTRACT_NAME} verified!`)
}
