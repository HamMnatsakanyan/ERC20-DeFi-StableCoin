// SPDX-License-Identifier: MIT

pragma solidity ^0.8.27;

import {ERC20Burnable, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoin is ERC20Burnable, Ownable {
    error DecetralizedStableCoin__MustBeMoreThanZero();
    error DecetralizedStableCoin__BurnAmountExceedsBalance();
    error DecetralizedStableCoin__AddressIsNull();

    constructor() ERC20("DecetralizedStableCoin", "DSC") {}

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);

        if (_amount <= 0) {
            revert DecetralizedStableCoin__MustBeMoreThanZero();
        }

        if (_amount > balance) {
            revert DecetralizedStableCoin__BurnAmountExceedsBalance();
        }

        super.burn(_amount);
    }

    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if (_to == address(0)) {
            revert DecetralizedStableCoin__AddressIsNull();
        }

        if (_amount <= 0) {
            revert DecetralizedStableCoin__MustBeMoreThanZero();
        }

        _mint(_to, _amount);
        return true;
    }
}
