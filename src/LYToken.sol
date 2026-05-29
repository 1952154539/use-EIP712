// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title LYToken - ERC20 token with EIP-2612 Permit extension
/// @notice Supports gasless token approvals via EIP-712 typed signatures
contract LYToken is ERC20, ERC20Permit, ERC20Burnable {
    constructor(uint256 initialSupply)
        ERC20("LYToken", "LYT")
        ERC20Permit("LYToken")
    {
        _mint(msg.sender, initialSupply);
    }

    /// @notice Mint additional tokens (owner only)
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
