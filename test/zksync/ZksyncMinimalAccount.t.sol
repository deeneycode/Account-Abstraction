// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ZKSyncMinimalAccount} from "src/zksync/ZksyncMinimalAccount.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {Transaction, MemoryTransactionHelper} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {BOOTLOADER_FORMAL_ADDRESS} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";

import {
    ACCOUNT_VALIDATION_SUCCESS_MAGIC
} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";


contract ZkSyncMinimalAccountTest is Test{
    using MessageHashUtils for bytes32;

    ZKSyncMinimalAccount account;
    ERC20Mock usdc;
    bytes4 constant EIP1271_SUCCESS_RETURN_VALUE = 0x1626ba7e;

    uint256 AMOUNT = 1e18;
    uint256 STARTING_AMOUNT = 1e18;
    bytes32 EMPTY_BYTES32 = bytes32(0);
    address  ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;


    function setUp() public {
        account = new ZKSyncMinimalAccount();
        account.transferOwnership(ANVIL_DEFAULT_ACCOUNT);
        usdc = new ERC20Mock();
        vm.deal(address(account), STARTING_AMOUNT);
    }

    function testZkOwnerCanExecuteCommands() public {
        // Arrange
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(account), AMOUNT);
        Transaction memory transaction = _createUnsignedTx(account.owner(), 113, dest, value, functionData);
        // Act
        vm.prank(account.owner());
        account.executeTransaction(EMPTY_BYTES32, EMPTY_BYTES32, transaction);
        // Assert
        assertEq(usdc.balanceOf(address(account)), AMOUNT);
    }

    function testZKValidateTransaction() public {
        // Arrange
        address dest = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(account), AMOUNT);
        Transaction memory transaction = _createUnsignedTx(account.owner(), 113, dest, value, functionData);
        transaction = _createSignedTx(transaction);
        // console.log("Transaction: ", transaction);

        // Act
        vm.prank(BOOTLOADER_FORMAL_ADDRESS);
        bytes4 magic = account.validateTransaction(EMPTY_BYTES32, EMPTY_BYTES32, transaction);
        // Assert
        assertEq(magic, ACCOUNT_VALIDATION_SUCCESS_MAGIC);
    }


    /** Helpers */
    function _createSignedTx(
        Transaction memory transaction
        ) internal view returns(Transaction memory)
        {
          bytes32 unsignedTransactionHash = MemoryTransactionHelper.encodeHash(transaction);
        // bytes32 digest = unsignedTransactionHash.toEthSignedMessageHash();
        uint8 v;
        bytes32 r;
        bytes32 s;
        uint256 ANVIL_DEFAULT_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        (v, r, s) = vm.sign(ANVIL_DEFAULT_KEY, unsignedTransactionHash);
        Transaction memory signedTransaction = transaction;
            signedTransaction.signature = abi.encodePacked(r, s, v);
            return signedTransaction;
        }

    function _createUnsignedTx
    (
        address from,
        uint8 transactionType,
        address to,
        uint256 value, 
        bytes memory data
    ) internal view returns(Transaction memory)
    {
        uint256 nonce = vm.getNonce(address(account));
        bytes32[] memory factoryDeps = new bytes32[](0);

        return Transaction({
            txType: transactionType, // type 113(0x71)
            from: uint256(uint160(from)),
            to: uint256(uint160(to)),
            gasLimit:11783233,
            gasPerPubdataByteLimit: 11783233,
            maxFeePerGas: 11783233,
            maxPriorityFeePerGas: 11783233,
            paymaster: 0,
            nonce: nonce,
            value: value,
            reserved:[uint256(0), uint256(0), uint256(0), uint256(0)],
            data: data,
            signature: hex"",
            factoryDeps: factoryDeps,
            paymasterInput: hex"",
            reservedDynamic: hex""
        });
    }

}