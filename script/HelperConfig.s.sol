// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    error HelperConfig__InvalidChainId();

    struct NetworkConfig {
        address entryPoint;
        address account;
    }

    uint256 constant ETH_SEPOLIA_CHAINID = 11155111;
    uint256 constant ZKSYNC_SEPOLIA_CHAINID = 300;
    uint256 constant LOCAL_CHAIN_ID = 31337;
    address constant BURNER_WALLET = 0x6C38b0767659E583064E797316E26B342591fddB;

    NetworkConfig public localNetworkConfig;

    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAINID] = getEthSepoliaConfig();
    }

    function getConfig() public view returns(NetworkConfig memory){
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 chainId) public view returns(NetworkConfig memory){
        if(chainId == LOCAL_CHAIN_ID){
            return getOrCreateAnvilEthConfig();
        } else if(networkConfigs[chainId].entryPoint != address(0)){
            return networkConfigs[chainId];
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    function getEthSepoliaConfig() public pure returns(NetworkConfig memory){
        return NetworkConfig({
            entryPoint: 
        });
    }

    function getZksyncSepoliaConfig() public pure returns(NetworkConfig memory){
        return NetworkConfig({entryPoint: address(0)});
    }

    function getOrCreateAnvilEthConfig() public view returns(NetworkConfig memory){
        if(localNetworkConfig.entryPoint == address(0)){
            return localNetworkConfig;
        }
    }
}