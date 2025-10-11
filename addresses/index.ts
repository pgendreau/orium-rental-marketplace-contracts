// import moonbeam from './moonbeam/index.json'
// import cronosTestnet from './cronosTestnet/index.json'
// import cronos from './cronos/index.json'
// import arbitrum from './arbitrum/index.json'
import polygon from './polygon/index.json'
import base from './base/index.json'

const config = {
  // moonbeam,
  // cronosTestnet,
  // cronos,
  // arbitrum,
  polygon,
  base
}

export default config

export type Network = keyof typeof config
