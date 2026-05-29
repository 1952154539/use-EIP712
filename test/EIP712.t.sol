// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {LYToken} from "../src/LYToken.sol";
import {TokenBank} from "../src/TokenBank.sol";
import {LYNFT} from "../src/LYNFT.sol";
import {NFTMarket} from "../src/NFTMarket.sol";

contract EIP712Test is Test {
    LYToken public token;
    TokenBank public bank;
    LYNFT public nft;
    NFTMarket public market;

    // Test addresses
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    // Private keys for signing
    uint256 public ownerKey = 0xA11CE;
    uint256 public aliceKey = 0xB0B;
    uint256 public bobKey = 0xC0C;

    // EIP-712 Permit typehash (matches OpenZeppelin ERC20Permit)
    bytes32 private constant PERMIT_TYPEHASH =
        keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

    // EIP-712 WhitelistPermit typehash (matches NFTMarket)
    bytes32 private constant WHITELIST_PERMIT_TYPEHASH =
        keccak256(
            "WhitelistPermit(address buyer,uint256 tokenId,uint256 price,uint256 deadline)"
        );

    function setUp() public {
        // Fund addresses
        vm.deal(owner, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // Set up proper addresses with private keys
        owner = vm.addr(ownerKey);
        alice = vm.addr(aliceKey);
        bob = vm.addr(bobKey);

        vm.deal(owner, 100 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        // Deploy token
        vm.startPrank(owner);
        token = new LYToken(1_000_000 * 10 ** 18);
        bank = new TokenBank(address(token));
        nft = new LYNFT();
        market = new NFTMarket(address(nft), address(token));
        vm.stopPrank();

        // Give alice some tokens
        vm.prank(owner);
        token.transfer(alice, 10_000 * 10 ** 18);

        // Mint NFTs to owner
        vm.startPrank(owner);
        nft.mint(owner, "ipfs://QmTest1");
        nft.mint(owner, "ipfs://QmTest2");
        vm.stopPrank();
    }

    // ============================================================
    //  Tests: EIP-2612 Token Permit + TokenBank permitDeposit
    // ============================================================

    function test_PermitDeposit_Success() public {
        uint256 depositAmount = 1000 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        console.log("=== Token Permit + Deposit Test ===");
        console.log("Alice initial token balance:", token.balanceOf(alice));
        console.log("Alice initial bank balance:", bank.balances(alice));
        console.log("Bank token balance:", token.balanceOf(address(bank)));

        // Alice signs a permit allowing the bank to spend her tokens
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceKey,
            address(token),
            alice,
            address(bank),
            depositAmount,
            deadline
        );

        // Bob (or anyone) can submit the permitDeposit on Alice's behalf
        vm.prank(bob);
        bank.permitDeposit(alice, depositAmount, deadline, v, r, s);

        console.log("--- After permitDeposit ---");
        console.log("Alice token balance:", token.balanceOf(alice));
        console.log("Alice bank balance:", bank.balances(alice));
        console.log("Bank token balance:", token.balanceOf(address(bank)));

        assertEq(token.balanceOf(alice), 10_000 * 10 ** 18 - depositAmount);
        assertEq(bank.balances(alice), depositAmount);
        assertEq(token.balanceOf(address(bank)), depositAmount);
    }

    function test_PermitDeposit_ExpiredPermit() public {
        uint256 depositAmount = 500 * 10 ** 18;
        uint256 deadline = block.timestamp; // Already expired

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceKey,
            address(token),
            alice,
            address(bank),
            depositAmount,
            deadline
        );

        vm.warp(block.timestamp + 1); // Move past deadline

        vm.prank(bob);
        vm.expectRevert();
        bank.permitDeposit(alice, depositAmount, deadline, v, r, s);
    }

    function test_PermitDeposit_WrongSigner() public {
        uint256 depositAmount = 500 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        // Someone else tries to use their own signature for Alice's tokens
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            bobKey,
            address(token),
            alice, // Claiming to be Alice
            address(bank),
            depositAmount,
            deadline
        );

        vm.prank(bob);
        vm.expectRevert(); // ERC20Permit: invalid signature
        bank.permitDeposit(alice, depositAmount, deadline, v, r, s);
    }

    function test_PermitDeposit_ThenWithdraw() public {
        uint256 depositAmount = 2000 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(
            aliceKey,
            address(token),
            alice,
            address(bank),
            depositAmount,
            deadline
        );

        vm.prank(bob);
        bank.permitDeposit(alice, depositAmount, deadline, v, r, s);

        // Alice withdraws
        uint256 aliceBalanceBefore = token.balanceOf(alice);
        vm.prank(alice);
        bank.withdraw(depositAmount);
        uint256 aliceBalanceAfter = token.balanceOf(alice);

        assertEq(aliceBalanceAfter - aliceBalanceBefore, depositAmount);
        assertEq(bank.balances(alice), 0);
    }

    function test_TraditionalDeposit() public {
        uint256 depositAmount = 500 * 10 ** 18;

        // Alice approves bank
        vm.prank(alice);
        token.approve(address(bank), depositAmount);

        // Alice deposits
        vm.prank(alice);
        bank.deposit(depositAmount);

        assertEq(bank.balances(alice), depositAmount);
        assertEq(token.balanceOf(address(bank)), depositAmount);
    }

    // ============================================================
    //  Tests: NFT Whitelist permitBuy
    // ============================================================

    function test_PermitBuy_Success() public {
        uint256 tokenId = 0;
        uint256 price = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        // Owner approves market and lists NFT
        vm.startPrank(owner);
        nft.approve(address(market), tokenId);
        market.list(tokenId, price);
        vm.stopPrank();

        console.log("=== NFT Whitelist Purchase Test ===");
        console.log("NFT owner before:", nft.ownerOf(tokenId));
        console.log("Alice token balance before:", token.balanceOf(alice));
        console.log("Owner token balance before:", token.balanceOf(owner));

        // Alice approves market for payment
        vm.prank(alice);
        token.approve(address(market), price);

        // Owner signs whitelist permit for Alice
        (uint8 v, bytes32 r, bytes32 s) = _signWhitelistPermit(
            ownerKey,
            address(market),
            alice,
            tokenId,
            price,
            deadline
        );

        // Alice buys via permitBuy
        vm.prank(alice);
        market.permitBuy(alice, tokenId, price, deadline, v, r, s);

        console.log("--- After permitBuy ---");
        console.log("NFT owner after:", nft.ownerOf(tokenId));
        console.log("Alice token balance after:", token.balanceOf(alice));
        console.log("Owner token balance after:", token.balanceOf(owner));

        assertEq(nft.ownerOf(tokenId), alice);
        assertEq(token.balanceOf(alice), 10_000 * 10 ** 18 - price);
        assertEq(token.balanceOf(owner), 990_000 * 10 ** 18 + price);
    }

    function test_PermitBuy_NotWhitelisted_Reverts() public {
        uint256 tokenId = 0;
        uint256 price = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        // Owner lists NFT
        vm.startPrank(owner);
        nft.approve(address(market), tokenId);
        market.list(tokenId, price);
        vm.stopPrank();

        // Bob tries to buy with a signature signed by a non-owner (himself)
        vm.prank(bob);
        token.approve(address(market), price);

        (uint8 v, bytes32 r, bytes32 s) = _signWhitelistPermit(
            bobKey, // Bob signs for himself (not the owner!)
            address(market),
            bob,
            tokenId,
            price,
            deadline
        );

        vm.prank(bob);
        vm.expectRevert("Invalid whitelist signature");
        market.permitBuy(bob, tokenId, price, deadline, v, r, s);
    }

    function test_PermitBuy_ExpiredPermit() public {
        uint256 tokenId = 0;
        uint256 price = 100 * 10 ** 18;
        uint256 deadline = block.timestamp; // Expired

        vm.startPrank(owner);
        nft.approve(address(market), tokenId);
        market.list(tokenId, price);
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(market), price);

        (uint8 v, bytes32 r, bytes32 s) = _signWhitelistPermit(
            ownerKey,
            address(market),
            alice,
            tokenId,
            price,
            deadline
        );

        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        vm.expectRevert("Permit expired");
        market.permitBuy(alice, tokenId, price, deadline, v, r, s);
    }

    function test_PermitBuy_ReplayAttack() public {
        uint256 tokenId = 0;
        uint256 price = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(owner);
        nft.approve(address(market), tokenId);
        market.list(tokenId, price);
        vm.stopPrank();

        (uint8 v, bytes32 r, bytes32 s) = _signWhitelistPermit(
            ownerKey,
            address(market),
            alice,
            tokenId,
            price,
            deadline
        );

        // First purchase succeeds
        vm.prank(alice);
        token.approve(address(market), price);
        vm.prank(alice);
        market.permitBuy(alice, tokenId, price, deadline, v, r, s);
        assertEq(nft.ownerOf(tokenId), alice);

        // Try to reuse the same permit - should fail because listing is no longer active
        // The permit is marked as used and the listing is no longer active
        bytes32 permitHash = keccak256(abi.encodePacked(alice, tokenId, deadline));
        assertTrue(market.usedPermits(permitHash));
    }

    function test_PermitBuy_WrongBuyer() public {
        uint256 tokenId = 0;
        uint256 price = 100 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(owner);
        nft.approve(address(market), tokenId);
        market.list(tokenId, price);
        vm.stopPrank();

        // Whitelist is for Alice, but Bob tries to use it
        (uint8 v, bytes32 r, bytes32 s) = _signWhitelistPermit(
            ownerKey,
            address(market),
            alice, // Authorized: Alice
            tokenId,
            price,
            deadline
        );

        vm.prank(bob);
        token.approve(address(market), price);

        vm.prank(bob);
        vm.expectRevert("Not authorized buyer");
        market.permitBuy(alice, tokenId, price, deadline, v, r, s);
    }

    function test_PermitBuy_PriceMismatch() public {
        uint256 tokenId = 0;
        uint256 listedPrice = 100 * 10 ** 18;
        uint256 wrongPrice = 50 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        vm.startPrank(owner);
        nft.approve(address(market), tokenId);
        market.list(tokenId, listedPrice);
        vm.stopPrank();

        vm.prank(alice);
        token.approve(address(market), wrongPrice);

        // Signature is for listedPrice but permitBuy uses wrongPrice
        (uint8 v, bytes32 r, bytes32 s) = _signWhitelistPermit(
            ownerKey,
            address(market),
            alice,
            tokenId,
            listedPrice, // Signed for 100
            deadline
        );

        // Signature was for listedPrice, but we pass wrongPrice - signature won't match
        vm.prank(alice);
        vm.expectRevert("Invalid whitelist signature");
        market.permitBuy(alice, tokenId, wrongPrice, deadline, v, r, s);
    }

    function test_FullFlow_MultiplePermitBuys() public {
        uint256 deadline = block.timestamp + 1 hours;

        // List two NFTs
        vm.startPrank(owner);
        nft.approve(address(market), 0);
        nft.approve(address(market), 1);
        market.list(0, 100 * 10 ** 18);
        market.list(1, 200 * 10 ** 18);
        vm.stopPrank();

        console.log("=== Multiple NFT Whitelist Purchase ===");

        // Alice buys token 0
        vm.prank(alice);
        token.approve(address(market), 100 * 10 ** 18);

        (uint8 v0, bytes32 r0, bytes32 s0) = _signWhitelistPermit(
            ownerKey, address(market), alice, 0, 100 * 10 ** 18, deadline
        );
        vm.prank(alice);
        market.permitBuy(alice, 0, 100 * 10 ** 18, deadline, v0, r0, s0);

        console.log("After purchase 1: NFT#0 owner =", nft.ownerOf(0));

        // Bob buys token 1
        vm.prank(owner);
        token.transfer(bob, 200 * 10 ** 18);
        vm.prank(bob);
        token.approve(address(market), 200 * 10 ** 18);

        (uint8 v1, bytes32 r1, bytes32 s1) = _signWhitelistPermit(
            ownerKey, address(market), bob, 1, 200 * 10 ** 18, deadline
        );
        vm.prank(bob);
        market.permitBuy(bob, 1, 200 * 10 ** 18, deadline, v1, r1, s1);

        console.log("After purchase 2: NFT#1 owner =", nft.ownerOf(1));

        assertEq(nft.ownerOf(0), alice);
        assertEq(nft.ownerOf(1), bob);

        console.log("=== All NFT transfers successful ===");
        console.log("Alice owns NFT#0:", nft.ownerOf(0) == alice);
        console.log("Bob owns NFT#1:", nft.ownerOf(1) == bob);
    }

    // ============================================================
    //  EIP-712 Signing Helpers
    // ============================================================

    /// @dev Sign an EIP-2612 Permit
    function _signPermit(
        uint256 signerKey,
        address tokenAddr,
        address ownerAddr,
        address spender,
        uint256 value,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        // Build domain separator (matching OpenZeppelin ERC20Permit)
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("LYToken")),
                keccak256(bytes("1")),
                block.chainid,
                tokenAddr
            )
        );

        // Get the current nonce
        uint256 nonce = token.nonces(ownerAddr);

        // Build struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                ownerAddr,
                spender,
                value,
                nonce,
                deadline
            )
        );

        // Build typed data hash (EIP-712)
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (v, r, s) = vm.sign(signerKey, digest);
    }

    /// @dev Sign a WhitelistPermit for NFTMarket
    function _signWhitelistPermit(
        uint256 signerKey,
        address marketAddr,
        address buyer,
        uint256 tokenId,
        uint256 price,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        // Build domain separator (matching NFTMarket)
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256(bytes("NFTMarket")),
                keccak256(bytes("1")),
                block.chainid,
                marketAddr
            )
        );

        // Build struct hash
        bytes32 structHash = keccak256(
            abi.encode(
                WHITELIST_PERMIT_TYPEHASH,
                buyer,
                tokenId,
                price,
                deadline
            )
        );

        // Build typed data hash (EIP-712)
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator, structHash)
        );

        (v, r, s) = vm.sign(signerKey, digest);
    }
}
