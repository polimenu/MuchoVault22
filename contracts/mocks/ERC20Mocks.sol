// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20{

    constructor() ERC20("USDC", "USDC"){ 
        _mint(msg.sender, 10000 * 10**6);
    }

    function decimals() public override pure returns(uint8){
        return 6;
    }

}

contract WETH is ERC20{

    constructor() ERC20("WETH", "WETH"){ 
        _mint(msg.sender, 100 * 10**18);
    }

    function decimals() public override pure returns(uint8){
        return 18;
    }

}

contract WBTC is ERC20{

    constructor() ERC20("WBTC", "WBTC"){ 
        _mint(msg.sender, 10 * 10**12);
    }

    function decimals() public override pure returns(uint8){
        return 12;
    }

}