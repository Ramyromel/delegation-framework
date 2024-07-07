// SPDX-License-Identifier: MIT AND Apache-2.0
pragma solidity 0.8.23;

import "forge-std/Test.sol";

import "../../src/utils/Types.sol";
import { Action } from "../../src/utils/Types.sol";
import { Counter } from "../utils/Counter.t.sol";
import { PasswordEnforcer } from "../utils/PasswordCaveatEnforcer.t.sol";
import { CaveatEnforcerBaseTest } from "./CaveatEnforcerBaseTest.t.sol";
import { EncoderLib } from "../../src/libraries/EncoderLib.sol";
import { IDelegationManager } from "../../src/interfaces/IDelegationManager.sol";
import { ICaveatEnforcer } from "../../src/interfaces/ICaveatEnforcer.sol";
import { MessageHashUtils } from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import { SigningUtilsLib } from "../utils/SigningUtilsLib.t.sol";

contract PasswordEnforcerTest is CaveatEnforcerBaseTest {
    ////////////////////////////// State //////////////////////////////
    PasswordEnforcer public passwordEnforcer;

    ////////////////////// Set up //////////////////////

    function setUp() public override {
        super.setUp();
        passwordEnforcer = new PasswordEnforcer();
        vm.label(address(passwordEnforcer), "Password Enforcer");
    }

    function test_userInputCorrectArgsWorks() public {
        Action memory action_;
        uint256 password_ = uint256(123456789);
        bytes memory terms_ = abi.encode(password_);
        address delegator_ = address(users.alice.deleGator);

        vm.startPrank(address(delegationManager));

        // First usage works well
        passwordEnforcer.beforeHook(terms_, abi.encode(password_), action_, bytes32(0), delegator_, address(0));
    }

    function test_userInputIncorrectArgs() public {
        Action memory action_;
        uint256 password_ = uint256(123456789);
        uint256 incorrectPassword_ = uint256(5154848789);
        bytes memory terms_ = abi.encode(password_);
        address delegator_ = address(users.alice.deleGator);

        vm.startPrank(address(delegationManager));

        vm.expectRevert("PasswordEnforcerError");

        passwordEnforcer.beforeHook(terms_, abi.encode(incorrectPassword_), action_, bytes32(0), delegator_, address(0));
    }

    //////////////////////  Integration  //////////////////////

    function test_userInputCorrectArgsWorksWithOnchainDelegation() public {
        uint256 initialValue_ = aliceDeleGatorCounter.count();
        // Create the action that would be executed
        Action memory action_ =
            Action({ to: address(aliceDeleGatorCounter), value: 0, data: abi.encodeWithSelector(Counter.increment.selector) });

        bytes memory inputTerms_ = abi.encode(uint256(12345));
        bytes memory password_ = abi.encode(uint256(12345));

        Caveat[] memory caveats_ = new Caveat[](1);
        caveats_[0] = Caveat({ args: password_, enforcer: address(passwordEnforcer), terms: inputTerms_ });
        Delegation memory delegation = Delegation({
            delegate: address(users.bob.deleGator),
            delegator: address(users.alice.deleGator),
            authority: ROOT_AUTHORITY,
            caveats: caveats_,
            salt: 0,
            signature: hex""
        });
        // Store delegation
        execute_UserOp(users.alice, abi.encodeWithSelector(IDelegationManager.delegate.selector, delegation));

        // Execute Bob's UserOp
        Delegation[] memory delegations_ = new Delegation[](1);
        delegations_[0] = delegation;

        // Enforcer allows the delegation
        invokeDelegation_UserOp(users.bob, delegations_, action_);
        // Validate that the count has increased by 1
        assertEq(aliceDeleGatorCounter.count(), initialValue_ + 1);
    }

    function test_userInputIncorrectArgsWithOnchainDelegation() public {
        uint256 initialValue_ = aliceDeleGatorCounter.count();
        // Create the action that would be executed
        Action memory action_ =
            Action({ to: address(aliceDeleGatorCounter), value: 0, data: abi.encodeWithSelector(Counter.increment.selector) });

        bytes memory inputTerms_ = abi.encode(uint256(12345));
        bytes memory incorrectPassword_ = abi.encode(uint256(123154245));

        Caveat[] memory caveats_ = new Caveat[](1);
        caveats_[0] = Caveat({ args: incorrectPassword_, enforcer: address(passwordEnforcer), terms: inputTerms_ });
        Delegation memory delegation = Delegation({
            delegate: address(users.bob.deleGator),
            delegator: address(users.alice.deleGator),
            authority: ROOT_AUTHORITY,
            caveats: caveats_,
            salt: 0,
            signature: hex""
        });
        // Store delegation
        execute_UserOp(users.alice, abi.encodeWithSelector(IDelegationManager.delegate.selector, delegation));

        // Execute Bob's UserOp
        Delegation[] memory delegations_ = new Delegation[](1);
        delegations_[0] = delegation;

        // Enforcer allows the delegation
        invokeDelegation_UserOp(users.bob, delegations_, action_);
        // Validate that the count has not increased
        assertEq(aliceDeleGatorCounter.count(), initialValue_);
    }

    // offchain delegation

    function test_userInputCorrectArgsWorksWithOffchainDelegation() public {
        uint256 initialValue_ = aliceDeleGatorCounter.count();
        // Create the action that would be executed
        Action memory action_ =
            Action({ to: address(aliceDeleGatorCounter), value: 0, data: abi.encodeWithSelector(Counter.increment.selector) });

        bytes memory inputTerms_ = abi.encode(uint256(12345));
        bytes memory password_ = abi.encode(uint256(12345));

        Caveat[] memory caveats_ = new Caveat[](1);
        caveats_[0] = Caveat({ args: password_, enforcer: address(passwordEnforcer), terms: inputTerms_ });
        Delegation memory delegation = Delegation({
            delegate: address(users.bob.deleGator),
            delegator: address(users.alice.deleGator),
            authority: ROOT_AUTHORITY,
            caveats: caveats_,
            salt: 0,
            signature: hex""
        });

        // Sign delegation
        bytes32 delegationHash_ = EncoderLib._getDelegationHash(delegation);
        bytes32 domainHash_ = delegationManager.getDomainHash();
        bytes32 typedDataHash_ = MessageHashUtils.toTypedDataHash(domainHash_, delegationHash_);
        uint256[] memory pks = new uint256[](1);
        pks[0] = users.alice.privateKey;
        bytes memory signature_ = SigningUtilsLib.signHash_MultiSig(pks, typedDataHash_);
        delegation.signature = signature_;

        // Execute Bob's UserOp
        Delegation[] memory delegations_ = new Delegation[](1);
        delegations_[0] = delegation;

        // Enforcer allows the delegation
        invokeDelegation_UserOp(users.bob, delegations_, action_);
        // Validate that the count has increased by 1
        assertEq(aliceDeleGatorCounter.count(), initialValue_ + 1);
    }

    function test_userInputIncorrectArgsWorksWithOffchainDelegation() public {
        uint256 initialValue_ = aliceDeleGatorCounter.count();
        // Create the action that would be executed
        Action memory action_ =
            Action({ to: address(aliceDeleGatorCounter), value: 0, data: abi.encodeWithSelector(Counter.increment.selector) });

        bytes memory inputTerms_ = abi.encode(uint256(12345));

        bytes memory incorrectPassword_ = abi.encode(uint256(123154245));

        Caveat[] memory caveats_ = new Caveat[](1);
        caveats_[0] = Caveat({ args: incorrectPassword_, enforcer: address(passwordEnforcer), terms: inputTerms_ });
        Delegation memory delegation = Delegation({
            delegate: address(users.bob.deleGator),
            delegator: address(users.alice.deleGator),
            authority: ROOT_AUTHORITY,
            caveats: caveats_,
            salt: 0,
            signature: hex""
        });

        // Sign delegation
        bytes32 delegationHash_ = EncoderLib._getDelegationHash(delegation);
        bytes32 domainHash_ = delegationManager.getDomainHash();
        bytes32 typedDataHash_ = MessageHashUtils.toTypedDataHash(domainHash_, delegationHash_);
        uint256[] memory pks = new uint256[](1);
        pks[0] = users.alice.privateKey;
        bytes memory signature_ = SigningUtilsLib.signHash_MultiSig(pks, typedDataHash_);
        delegation.signature = signature_;

        // Execute Bob's UserOp
        Delegation[] memory delegations_ = new Delegation[](1);
        delegations_[0] = delegation;

        // Enforcer allows the delegation
        invokeDelegation_UserOp(users.bob, delegations_, action_);
        // Validate that the count has NOT increased
        assertEq(aliceDeleGatorCounter.count(), initialValue_);
    }

    function _getEnforcer() internal view override returns (ICaveatEnforcer) {
        return ICaveatEnforcer(address(passwordEnforcer));
    }
}