// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title TokenBank - Deposit token with EIP-2612 permit support
/// @notice Users can deposit tokens either via traditional approve+deposit or gasless permitDeposit
contract TokenBank is Ownable {
    IERC20 public immutable token;

    mapping(address => uint256) public balances;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    constructor(address _token) Ownable(msg.sender) {
        token = IERC20(_token);
    }

    /// @notice Traditional deposit: user must approve first, then call deposit
    function deposit(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        balances[msg.sender] += amount;
        emit Deposited(msg.sender, amount);
    }

    /// @notice Gasless deposit using EIP-2612 permit signature
    /// @param owner The token owner who signed the permit
    /// @param value The amount of tokens to approve and deposit
    /// @param deadline The permit deadline timestamp
    /// @param v Permit signature v
    /// @param r Permit signature r
    /// @param s Permit signature s
    function permitDeposit(
        address owner,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(value > 0, "Amount must be > 0");

        // Execute permit to approve this contract as spender
        IERC20Permit(address(token)).permit(
            owner,
            address(this),
            value,
            deadline,
            v,
            r,
            s
        );

        // Transfer tokens from owner to bank
        require(
            token.transferFrom(owner, address(this), value),
            "Transfer failed"
        );
        balances[owner] += value;
        emit Deposited(owner, value);
    }

    /// @notice Withdraw deposited tokens
    function withdraw(uint256 amount) external {
        require(amount > 0, "Amount must be > 0");
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        require(token.transfer(msg.sender, amount), "Transfer failed");
        emit Withdrawn(msg.sender, amount);
    }
}
