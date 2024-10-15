// SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployMinimalAccount} from "script/DeployMinimalAccount.s.sol";
import {MinimalAccount} from "src/ethereum/MinimalAccount.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {SendPackedUserOp} from "script/SendPackedUserOp.s.sol";
import {ERC20Mock} from "lib/openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "lib/openzeppelin-contracts/contracts/utils/cryptography/MessageHashUtils.sol";
import {IEntryPoint} from "lib/account-abstraction/contracts/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "lib/account-abstraction/contracts/interfaces/PackedUserOperation.sol";

contract MinimumAccountTest is Test {
    using MessageHashUtils for bytes32;

    DeployMinimalAccount deployer;
    MinimalAccount minimalAccount;
    HelperConfig helperConfig;
    ERC20Mock usdc;
    SendPackedUserOp sendUserOp;

    uint256 constant AMOUNT = 1e18;

    address public USER = makeAddr("USER");

    function setUp() public {
        deployer = new DeployMinimalAccount();
        (helperConfig, minimalAccount) = deployer.deployMinimalAccount();
        usdc = new ERC20Mock();
        sendUserOp = new SendPackedUserOp();
    }

    //USDC Approval
    // msg.sender -> Minimal Account
    // approve some amount
    // USDC contract
    // come from the entry point

    function testOwnerCanExecuteCommands() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address to = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        // Act
        vm.prank(minimalAccount.owner());
        minimalAccount.execute(to, value, functionData);
        // Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testNotOwnerCannotExecuteCommand() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address to = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        // Act
        vm.prank(USER);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPointAndOwner.selector);
        minimalAccount.execute(to, value, functionData);
    }

    function testRecoverSignedOp() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address to = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData = abi.encodeWithSelector(MinimalAccount.execute.selector, to, value, functionData);
        PackedUserOperation memory packedUserOp =
            sendUserOp.generateSignedUserOperation(executeCallData, helperConfig.getConfig(), address(minimalAccount));
        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);
        // Act
        address actualSigner = ECDSA.recover(userOperationHash.toEthSignedMessageHash(), packedUserOp.signature);
        // Assert
        assertEq(actualSigner, minimalAccount.owner());
    }

    // sign user ops
    // call validate user ops
    // assert
    function testValidateUserOps() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address to = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData = abi.encodeWithSelector(MinimalAccount.execute.selector, to, value, functionData);
        PackedUserOperation memory packedUserOp =
            sendUserOp.generateSignedUserOperation(executeCallData, helperConfig.getConfig(), address(minimalAccount));
        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);

        // Act
        uint256 missingAccountFunds = 1e18;
        vm.prank(helperConfig.getConfig().entryPoint);
        uint256 validationData = minimalAccount.validateUserOp(packedUserOp, userOperationHash, missingAccountFunds);

        // Assert
        assertEq(validationData, 0);
    }

    function testEntryPointCanExecuteCommand() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address to = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData = abi.encodeWithSelector(MinimalAccount.execute.selector, to, value, functionData);
        PackedUserOperation memory packedUserOp =
            sendUserOp.generateSignedUserOperation(executeCallData, helperConfig.getConfig(), address(minimalAccount));

        vm.deal(address(minimalAccount), 1e18);
        // Act
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = packedUserOp;
        vm.prank(USER);
        IEntryPoint(helperConfig.getConfig().entryPoint).handleOps(ops, payable(USER));
        //Assert
        assertEq(usdc.balanceOf(address(minimalAccount)), AMOUNT);
    }

    function testRevertIfUserNotFromEntryPoint() public {
        // Arrange
        assertEq(usdc.balanceOf(address(minimalAccount)), 0);
        address to = address(usdc);
        uint256 value = 0;
        bytes memory functionData = abi.encodeWithSelector(ERC20Mock.mint.selector, address(minimalAccount), AMOUNT);
        bytes memory executeCallData = abi.encodeWithSelector(MinimalAccount.execute.selector, to, value, functionData);
        PackedUserOperation memory packedUserOp =
            sendUserOp.generateSignedUserOperation(executeCallData, helperConfig.getConfig(), address(minimalAccount));
        bytes32 userOperationHash = IEntryPoint(helperConfig.getConfig().entryPoint).getUserOpHash(packedUserOp);

        // Act
        uint256 missingAmount = 1e18;
        vm.prank(USER);
        vm.expectRevert(MinimalAccount.MinimalAccount__NotFromEntryPoint.selector);
        minimalAccount.validateUserOp(packedUserOp, userOperationHash, missingAmount);
    }
}
