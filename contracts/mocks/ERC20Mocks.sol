// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.9.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract USDC is ERC20{

    constructor() ERC20("USDC", "USDC"){ 
        _mint(msg.sender, 100000 * 10**6);
    }

    function decimals() public override pure returns(uint8){
        return 6;
    }

    function mint(address _to, uint256 _amount) external{
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external{
        _burn(_from, _amount);
    }
}

contract USDT is ERC20{

    constructor() ERC20("USDT", "USDT"){ 
        _mint(msg.sender, 100000 * 10**6);
    }

    function decimals() public override pure returns(uint8){
        return 6;
    }

    function mint(address _to, uint256 _amount) external{
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external{
        _burn(_from, _amount);
    }
}

contract DAI is ERC20{

    constructor() ERC20("DAI", "DAI"){ 
        _mint(msg.sender, 100000 * 10**6);
    }

    function decimals() public override pure returns(uint8){
        return 6;
    }

    function mint(address _to, uint256 _amount) external{
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external{
        _burn(_from, _amount);
    }
}

contract WETH is ERC20{

    constructor() ERC20("WETH", "WETH"){ 
        _mint(msg.sender, 1000 * 10**18);
    }

    function decimals() public override pure returns(uint8){
        return 18;
    }

    function mint(address _to, uint256 _amount) external{
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external{
        _burn(_from, _amount);
    }

}

contract WBTC is ERC20{

    constructor() ERC20("WBTC", "WBTC"){ 
        _mint(msg.sender, 100 * 10**12);
    }

    function decimals() public override pure returns(uint8){
        return 12;
    }

    function mint(address _to, uint256 _amount) external{
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external{
        _burn(_from, _amount);
    }

}





contract GLP is ERC20{

    constructor() ERC20("GLP", "GLP"){ 
        //_mint(msg.sender, 1000000 * 10**18);
    }

    function decimals() public override pure returns(uint8){
        return 18;
    }
    
    function mint(address _to, uint256 _amount) external{
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external{
        _burn(_from, _amount);
    }
}