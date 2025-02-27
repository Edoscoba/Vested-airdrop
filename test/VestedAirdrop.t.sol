// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/VestedAirdrop.sol";
import "../src/Token.sol";

contract VestedClaimsTest is Test {
    Token public token;
    VestedClaims public airdrop;
    address public owner;
    address public user1;
    uint256 public amount;
    bytes32[] public proof;

    // helper: convert whole tokens to wei (assuming 18 decimals)
    function toWei(uint256 amt) internal pure returns (uint256) {
        return amt * 1e18;
    }

    // setUp runs before each test
    function setUp() public {
        owner = address(this); // test contract will be owner
        token = new Token();
        // set vesting parameters: vesting lasts 90 days (3 months)
        uint256 vestingStart = block.timestamp;
        uint256 vestingEnd = block.timestamp + 90 days;
        // use an arbitrary user address for testing
        user1 = address(0x123);
        // set claim amount (for example, 1000 tokens)
        amount = toWei(1000);
        // For a single-leaf Merkle tree, the leaf is:
        // keccak256(abi.encodePacked(bytes20(user1), bytes32(amount)))
        bytes32 leaf = keccak256(abi.encodePacked(bytes20(user1), bytes32(amount)));
        // In a one-element tree, the merkle proof is empty.
        proof = new bytes32[](0);
        // Deploy the vesting contract with the initial merkle root = leaf.
        airdrop = new VestedClaims(leaf, address(token), vestingStart, vestingEnd);
    }

    function testIncrement() public {
        // token.name() should equal "Token"
        assertEq(keccak256(bytes(token.name())), keccak256(bytes("Token")));
        // airdrop.token() must equal the token's address.
        assertEq(airdrop.token(), address(token));
    }

    function testSetMerkleRoot() public {
        // set merkle root to a new value (from the Python test)
        bytes32 newMerkleRoot = 0x84cef39a349765463ae54b9e7060205f4075ec9abed7f7ceac12f9f266f87062;
        airdrop.set_merkle_root(newMerkleRoot);
        assertEq(airdrop.merkle_root(), newMerkleRoot);
    }

    function testClaim() public {
        // --- First claim (TGE): should get 31% of tokens ---
        airdrop.claim(user1, amount, proof);
        uint256 userBalance = token.balanceOf(user1);
        uint256 expected = (amount * 31) / 100;
        assertEq(userBalance, expected);

        // --- Claim again immediately: should revert with "Nothing to claim" ---
        vm.expectRevert("Nothing to claim");
        airdrop.claim(user1, amount, proof);

        // --- After 30 days ---
        vm.warp(block.timestamp + 30 days);
        airdrop.claim(user1, amount, proof);
        userBalance = token.balanceOf(user1);
        uint256 linearVesting = (amount * 69) / 100;
        expected = (amount * 31) / 100 + (linearVesting * 30 days) / (90 days);
        assertEq(userBalance, expected);

        // --- After 60 days total ---
        vm.warp(block.timestamp + 30 days);
        airdrop.claim(user1, amount, proof);
        expected = (amount * 31) / 100 + (linearVesting * 60 days) / (90 days);
        assertEq(token.balanceOf(user1), expected);

        // --- After 90 days total ---
        vm.warp(block.timestamp + 30 days);
        airdrop.claim(user1, amount, proof);
        expected = amount;
        assertEq(token.balanceOf(user1), expected);

        // --- Further claims should revert ---
        vm.warp(block.timestamp + 30 days);
        vm.expectRevert("Nothing to claim");
        airdrop.claim(user1, amount, proof);
    }

    function testClaimAll() public {
        // Skip vesting and jump straight to 90 days.
        vm.warp(block.timestamp + 90 days);
        airdrop.claim(user1, amount, proof);
        assertEq(token.balanceOf(user1), amount);
        vm.expectRevert("Nothing to claim");
        airdrop.claim(user1, amount, proof);
    }

    function testClaimIrregularTime() public {
        // Claim at irregular time intervals.
        // claim at 1 day
        vm.warp(block.timestamp + 1 days);
        airdrop.claim(user1, amount, proof);
        // claim at 12 days total (advance 11 days)
        vm.warp(block.timestamp + 11 days);
        airdrop.claim(user1, amount, proof);
        // claim at 35 days total (advance 23 days)
        vm.warp(block.timestamp + 23 days);
        airdrop.claim(user1, amount, proof);
        // claim at 60 days total (advance 25 days)
        vm.warp(block.timestamp + 25 days);
        airdrop.claim(user1, amount, proof);
        // claim at 892 days total (advance 832 days)
        vm.warp(block.timestamp + 832 days);
        airdrop.claim(user1, amount, proof);
        // Full amount should be claimed.
        assertEq(token.balanceOf(user1), amount);
        // Further claims revert.
        vm.expectRevert("Nothing to claim");
        airdrop.claim(user1, amount, proof);
    }

    function testCannotClaimBeforeStart() public {
        // Warp to time 0 (before vesting start) and expect revert.
        vm.warp(0);
        vm.expectRevert("Claiming is not available yet");
        airdrop.claim(user1, amount, proof);
    }

    function testClaimableAmount() public {
        // At vesting start, only 31% should be claimable.
        uint256 claimable = airdrop.claimable_amount(user1, amount);
        uint256 expected = (amount * 31) / 100;
        assertEq(claimable, expected);

        uint256 linearVesting = (amount * 69) / 100;
        uint256 startTime = block.timestamp;

        // After 30 days:
        vm.warp(startTime + 30 days);
        claimable = airdrop.claimable_amount(user1, amount);
        expected = (amount * 31) / 100 + (linearVesting * 30 days) / (90 days);
        assertEq(claimable, expected);

        // After 60 days:
        vm.warp(startTime + 60 days);
        claimable = airdrop.claimable_amount(user1, amount);
        expected = (amount * 31) / 100 + (linearVesting * 60 days) / (90 days);
        assertEq(claimable, expected);

        // After 90 days:
        vm.warp(startTime + 90 days);
        claimable = airdrop.claimable_amount(user1, amount);
        expected = amount;
        assertEq(claimable, expected);

        // After 120 days, still full amount:
        vm.warp(startTime + 120 days);
        claimable = airdrop.claimable_amount(user1, amount);
        expected = amount;
        assertEq(claimable, expected);
    }

    function testClaimableAmountWithClaims() public {
        uint256 linearVesting = (amount * 69) / 100;
        uint256 claimable = airdrop.claimable_amount(user1, amount);
        uint256 expected = (amount * 31) / 100;
        assertEq(claimable, expected);

        // Claim initial TGE amount.
        airdrop.claim(user1, amount, proof);
        assertEq(token.balanceOf(user1), (amount * 31) / 100);

        // Claiming immediately again should revert.
        vm.expectRevert("Nothing to claim");
        airdrop.claim(user1, amount, proof);
        claimable = airdrop.claimable_amount(user1, amount);
        assertEq(claimable, 0);

        // After 30 days.
        vm.warp(block.timestamp + 30 days);
        claimable = airdrop.claimable_amount(user1, amount);
        expected = (linearVesting * 30 days) / (90 days);
        assertEq(claimable, expected);
        airdrop.claim(user1, amount, proof);
        assertEq(
            token.balanceOf(user1),
            (amount * 31) / 100 + (linearVesting * 30 days) / (90 days)
        );

        // After 60 days total.
        vm.warp(block.timestamp + 30 days);
        claimable = airdrop.claimable_amount(user1, amount);
        expected = (linearVesting * 30 days) / (90 days);
        assertEq(claimable, expected);
        airdrop.claim(user1, amount, proof);
        assertEq(
            token.balanceOf(user1),
            (amount * 31) / 100 + (linearVesting * 60 days) / (90 days)
        );

        // After 90 days total.
        vm.warp(block.timestamp + 30 days);
        claimable = airdrop.claimable_amount(user1, amount);
        expected = (linearVesting * 30 days) / (90 days);
        assertEq(claimable, expected);
        airdrop.claim(user1, amount, proof);
        assertEq(token.balanceOf(user1), amount);

        // No further claimable amount.
        vm.warp(block.timestamp + 30 days);
        vm.expectRevert("Nothing to claim");
        airdrop.claim(user1, amount, proof);
        claimable = airdrop.claimable_amount(user1, amount);
        assertEq(claimable, 0);
    }

    function testRescueTokens() public {
        uint256 rescueAmt = toWei(1000);
        uint256 airdropBal = token.balanceOf(address(airdrop));
        airdrop.rescue_tokens(address(token), rescueAmt);
        assertEq(token.balanceOf(address(airdrop)), airdropBal - rescueAmt);
    }

    function testSetTimestamp() public {
        uint256 currentTime = airdrop.vesting_start_time();
        assertTrue(currentTime != 0);
        // Use cheat code vm.store to update the storage slot of vesting_start_time (assumed to be slot 0)
        vm.store(address(airdrop), bytes32(uint256(0)), bytes32(uint256(0)));
        assertEq(airdrop.vesting_start_time(), 0);
    }

    function testOwnableFunctions() public {
        address notOwner = address(0x456);
        vm.prank(notOwner);
        vm.expectRevert("Only owner can call this function");
        airdrop.set_merkle_root(0x0);

        vm.prank(notOwner);
        vm.expectRevert("Only owner can call this function");
        airdrop.rescue_tokens(address(token), 0);
    }
}
