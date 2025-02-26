// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/*
@title Vested Claims
@notice This contract is used to distribute tokens to users, 31% TGE, 69% linear vesting
*/
contract VestedClaims {
    // Timestamp at which the vesting period starts
    uint256 public vesting_start_time;
    // Timestamp at which the vesting period ends
    uint256 public vesting_end_time;
    // The Merkle root of the tree used to verify the inclusion of a user in the list of recipients
    bytes32 public merkle_root;
    // The address of the token being distributed
    address public token;
    // The address of the owner of the contract
    address public owner;
    // Mapping of users to the amount of tokens they have claimed
    mapping(address => uint256) public claimed_amount;

    // Event emitted when a user claims tokens
    event Claimed(address indexed user, uint256 amount);
    // Event emitted when the Merkle root is updated
    event MerkleRootUpdated(bytes32 indexed merkle_root);
    // Event emitted when tokens are rescued
    event TokensRescued(address indexed to, uint256 amount);

    constructor(
        bytes32 _merkle_root,
        address _token,
        uint256 _vesting_start_time,
        uint256 _vesting_end_time
    ) {
        // Set the Merkle root
        merkle_root = _merkle_root;
        // Set the token address
        token = _token;
        // Set the vesting start time
        vesting_start_time = _vesting_start_time;
        // Set the vesting end time
        vesting_end_time = _vesting_end_time;
        // Set the owner
        owner = msg.sender;
        // Emit the event
        emit MerkleRootUpdated(_merkle_root);
    }

    // Modifier to check that the caller is the owner
    modifier onlyOwner() {
        // Check that the caller is the owner
        require(msg.sender == owner, "Only owner can call this function");
        // Execute the code
        _;
    }

    // Internal function to calculate the hash of a pair of bytes32
    function _hash_pair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        // Check if a is less than b
        if (uint256(a) < uint256(b)) {
            // Return the hash of a and b
            return keccak256(abi.encodePacked(a, b));
        }
        // Return the hash of b and a
        return keccak256(abi.encodePacked(b, a));
    }

    // Internal function to verify a proof
    function _verify_proof(bytes32[] memory proof, bytes32 leaf) internal view returns (bool) {
        // Initialize the hash to the leaf
        bytes32 computed_hash = leaf;
        // Iterate over the proof
        for (uint256 i = 0; i < proof.length; i++) {
            // Update the hash with the i-th element of the proof
            computed_hash = _hash_pair(computed_hash, proof[i]);
        }
        // Return true if the computed hash is equal to the Merkle root
        return computed_hash == merkle_root;
    }

    // Public function to verify a proof
    function verify_proof(
        address user,
        uint256 amount,
        bytes32[] memory proof
    ) public view returns (bool) {
        // Compute the leaf
        bytes32 leaf = keccak256(abi.encodePacked(bytes20(user), bytes32(amount)));
        // Return the result of the verification
        return _verify_proof(proof, leaf);
    }

    // Public function to calculate the vested amount
    function _calculate_vested_amount(uint256 total_amount) public view returns (uint256) {
        uint256 current_time = block.timestamp;
        // If the current time is greater than the vesting end time, return the total amount
        if (current_time >= vesting_end_time) {
            return total_amount;
        }
        // Calculate the vesting duration
        uint256 vesting_duration = vesting_end_time - vesting_start_time;
        // Calculate the elapsed time
        uint256 elapsed = current_time - vesting_start_time;
        // Calculate the instant release amount
        uint256 instant_release = (total_amount * 31) / 100;
        // Calculate the linear vesting amount
        uint256 linear_vesting = (total_amount * 69) / 100;
        // Calculate the vested amount
        uint256 vested = instant_release + (linear_vesting * elapsed) / vesting_duration;
        // Return the vested amount
        return vested;
    }

    // Public function to set the Merkle root
    function set_merkle_root(bytes32 _merkle_root) external onlyOwner {
        // Set the Merkle root
        merkle_root = _merkle_root;
        // Emit the event
        emit MerkleRootUpdated(_merkle_root);
    }

    // Public function to rescue tokens
    function rescue_tokens(address to, uint256 amount) external onlyOwner {
        // Emit the event
        emit TokensRescued(to, amount);
        // Transfer the tokens
        require(IERC20(token).transfer(to, amount), "Transfer failed");
    }

    // Public function to claim tokens
    function claim(
        address user,
        uint256 total_amount,
        bytes32[] memory proof
    ) external returns (bool) {
        // Verify the proof
        require(verify_proof(user, total_amount, proof), "Invalid proof");
        // Check that the current time is greater than the vesting start time
        require(block.timestamp >= vesting_start_time, "Claiming is not available yet");

        // Calculate the current amount
        uint256 current_amount = claimed_amount[user];
        // Calculate the vested amount
        uint256 vested = _calculate_vested_amount(total_amount);
        // Calculate the claimable amount
        uint256 claimable = 0;
        if (vested > current_amount) {
            claimable = vested - current_amount;
        }
        // Check that the claimable amount is greater than 0
        require(claimable > 0, "Nothing to claim");

        // Update the claimed amount
        claimed_amount[user] += claimable;
        // Check that the claimed amount is less than or equal to the total amount
        require(claimed_amount[user] <= total_amount, "Claimed amount exceeds total amount");
        // Emit the event
        emit Claimed(user, claimable);

        // Transfer the tokens
        require(IERC20(token).transfer(user, claimable), "Transfer failed");
        // Return true
        return true;
    }

    // Public function to calculate the claimable amount
    function claimable_amount(address user, uint256 total_amount) external view returns (uint256) {
        // Check that the current time is greater than the vesting start time
        require(block.timestamp >= vesting_start_time, "Claiming is not available yet");

        // Calculate the current amount
        uint256 current_amount = claimed_amount[user];
        // Calculate the vested amount
        uint256 vested = _calculate_vested_amount(total_amount);
        // Calculate the claimable amount
        uint256 claimable = 0;
        if (vested > current_amount) {
            claimable = vested - current_amount;
        }
        // Return the claimable amount
        return claimable;
    }
}

