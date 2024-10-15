// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {
    IAccount,
    ACCOUNT_VALIDATION_SUCCESS_MAGIC
} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/IAccount.sol";
import {
    MemoryTransactionHelper,
    Transaction
} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/MemoryTransactionHelper.sol";
import {SystemContractsCaller} from
    "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/SystemContractsCaller.sol";
import {
    NONCE_HOLDER_SYSTEM_CONTRACT,
    BOOTLOADER_FORMAL_ADDRESS,
    DEPLOYER_SYSTEM_CONTRACT
} from "lib/foundry-era-contracts/src/system-contracts/contracts/Constants.sol";
import {INonceHolder} from "lib/foundry-era-contracts/src/system-contracts/contracts/interfaces/INonceHolder.sol";
import {Utils} from "lib/foundry-era-contracts/src/system-contracts/contracts/libraries/Utils.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * lifecycle of a type 113(0x71) transaction
 * msg.sender is the bootloader system contract
 *
 * Phase 1
 * 1. The user sends the transaction to the "zkSync API client" (sort of a "light node")
 * 2. The zkSync API client checks to see the nonce is querying the NonceHolder system contract
 * 3. The zkSync API client calls validateTransaction, which must update the nonce
 * 4. The zkSync API client checks the nonce is updated
 * 5. The zkSync API client calls payForTransaction or prepareForPaymaster and validateAndPayForPaymasterTransaction
 * 6. The zksync API client verifies that the bootloader get paid
 *
 *
 *  Phase 2 Execution
 * 7. The zksync API client passes the validated transaction to the main node / sequence (as of today, they are the same)
 * 8. The main node calls executeTransaction
 * 9. If a paymaster was used, the postTransaction method is called on the paymaster
 */
contract ZKSyncMinimalAccount is IAccount, Ownable {
    using MemoryTransactionHelper for Transaction;

    /**
     * Errors
     */
    error ZKSyncMinimalAccount__NotEnoughBalanceForFee();
    error ZKSyncMinimalAccount__ExecutionFailed();
    error ZkSyncMinimalAccount__NotFromBootloader();
    error ZkSyncMinimalAccount__NotFromBootloaderOrOwner();
    error ZKSyncMinimalAccount__PaymentFailed();
    error ZkSyncMinimalAccount__InvalidSignature();
    /**
     * Modifier
     */
    modifier requireFromBootLoader() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS) {
            revert ZkSyncMinimalAccount__NotFromBootloader();
        }
        _;
    }

    modifier requireFromBootLoaderOrOwner() {
        if (msg.sender != BOOTLOADER_FORMAL_ADDRESS && msg.sender != owner()) {
            revert ZkSyncMinimalAccount__NotFromBootloaderOrOwner();
        }
        _;
    }

    constructor() Ownable(msg.sender) {}
    receive() external payable {}

    /**
     * External functions
     */
    /// @notice Called by the bootloader to validate that an account agrees to process the transaction
    /// (and potentially pay for it).
    /// @param _txHash The hash of the transaction to be used in the explorer
    /// @param _suggestedSignedHash The hash of the transaction is signed by EOAs
    /// @param _transaction The transaction itself
    /// @return magic The magic value that should be equal to the signature of this function
    /// if the user agrees to proceed with the transaction.
    /// @dev The developer should strive to preserve as many steps as possible both for valid
    /// and invalid transactions as this very method is also used during the gas fee estimation
    /// (without some of the necessary data, e.g. signature).
    /**
     *
     * @notice Must increase the nonce
     * @notice must validate the transaction (check the owner signed the transaction)
     * @notice also check to see if we have enough money in the account to pay for the transaction since, we dont have a paymaster.
     */
    function validateTransaction(bytes32, /*_txHash*/ bytes32, /*_suggestedSignedHash*/ Transaction memory _transaction)
        external
        payable
        requireFromBootLoader
        returns(bytes4 /*magic*/)
    {
        _validateTransaction(_transaction);
    }

    function executeTransaction(bytes32, /*_txHash*/ bytes32, /*_suggestedSignedHash*/ Transaction memory _transaction)
        external
        payable
        requireFromBootLoaderOrOwner
    {
        _executeTransaction(_transaction);
    }

    // There is no point in providing possible signed hash in the `executeTransactionFromOutside` method,
    // since it typically should not be trusted.
    function executeTransactionFromOutside(Transaction memory _transaction) external payable
    {
        bytes4 magic =_validateTransaction(_transaction);
        if(magic != ACCOUNT_VALIDATION_SUCCESS_MAGIC){
            revert ZkSyncMinimalAccount__InvalidSignature();
        }
        _executeTransaction(_transaction);
    }

    function payForTransaction(bytes32 /*_txHash*/, bytes32 /*_suggestedSignedHash*/, Transaction memory _transaction)
        external
        payable
    {
        bool success = _transaction.payToTheBootloader();
        if(!success){
            revert ZKSyncMinimalAccount__PaymentFailed();
        }
    }

    function prepareForPaymaster(bytes32 _txHash, bytes32 _possibleSignedHash, Transaction memory _transaction)
        external
        payable
    {}

    /**
     * Internal functions
     */
    function _validateTransaction(Transaction memory _transaction) internal returns (bytes4 magic) {
        // call the nonceholder
        // increament the nonce
        // call(x,y,z)-> systemContractCaller
        SystemContractsCaller.systemCallWithPropagatedRevert(
            uint32(gasleft()),
            address(NONCE_HOLDER_SYSTEM_CONTRACT),
            0,
            abi.encodeCall(INonceHolder.incrementMinNonceIfEquals, (_transaction.nonce))
        );
        // check for fee
        uint256 totalrequiredBalance = _transaction.totalRequiredBalance();
        if (totalrequiredBalance > address(this).balance) {
            revert ZKSyncMinimalAccount__NotEnoughBalanceForFee();
        }
        // check for signature
        bytes32 txHash = _transaction.encodeHash();
        // bytes hashMessage memory = MessageHashUtils.toEthSignedMessageHash(txHash); // not needed.
        address signer = ECDSA.recover(txHash, _transaction.signature);
        bool isValidSigner = signer == owner();
        if (isValidSigner) {
            magic = ACCOUNT_VALIDATION_SUCCESS_MAGIC;
        } else {
            magic = bytes4(0);
        }
        // return "magic" number
        return magic;
    }

    function _executeTransaction(Transaction memory _transaction) internal
    {
        address to = address(uint160(_transaction.to));
        uint128 value = Utils.safeCastToU128(_transaction.value);
        bytes memory data = _transaction.data;

        if(to == address(DEPLOYER_SYSTEM_CONTRACT)) {
            uint32 gas = Utils.safeCastToU32(gasleft());
            SystemContractsCaller.systemCallWithPropagatedRevert(gas, to, value, data);   
        } else {
           bool success;
        assembly {
            success := call(gas(), to, value, add(data, 0x20), mload(data), 0, 0)
        }
        if(!success) {
            revert ZKSyncMinimalAccount__ExecutionFailed();
        } 
        }

    }
}
