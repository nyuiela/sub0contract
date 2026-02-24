// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TestERC20
 * @notice A simple mintable ERC20 token for testing purposes
 * @dev Owner can mint tokens to any address
 */
contract TestERC20 is ERC20, Ownable {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_, address initialOwner)
        ERC20(name, symbol)
        Ownable(initialOwner)
    {
        _decimals = decimals_;
    }

    /**
     * @notice Mint tokens to an address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }

    /**
     * @notice Mint tokens to multiple addresses
     * @param recipients Array of addresses to mint to
     * @param amounts Array of amounts to mint (must match recipients length)
     */
    function mintBatch(address[] calldata recipients, uint256[] calldata amounts) external onlyOwner {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    /**
     * @dev Returns the number of decimals used to get its user representation
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
}
