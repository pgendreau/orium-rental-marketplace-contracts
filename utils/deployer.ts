import * as dotenv from 'dotenv'
import { ethers, network } from 'hardhat'

dotenv.config()

const networkConfig: any = network.config

export const provider = new ethers.JsonRpcProvider(networkConfig.url || '')
export const deployer = new ethers.Wallet(process.env['PROD_PRIVATE_KEY']).connect(provider)
