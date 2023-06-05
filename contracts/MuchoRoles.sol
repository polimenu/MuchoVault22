// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

abstract contract MuchoRoles is AccessControl, Ownable{
    bytes32 public constant CONTRACT_OWNER = keccak256("CONTRACT_OWNER");
    bytes32 public constant TRADER = keccak256("TRADER");

    address private _protocolOwner;

    function protocolOwner() public view returns(address){
        return _protocolOwner;
    }

    constructor(){
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _protocolOwner = msg.sender;
        //_setRoleAdmin(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    modifier onlyAdmin(){
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "MuchoRoles: Only for admin");
        _;
    }

    modifier onlyContractOwner(){
        require(hasRole(CONTRACT_OWNER, msg.sender), "MuchoRoles: Only for contract owner");
        _;
    }

    modifier onlyContractOwnerOrAdmin(){
        require(hasRole(CONTRACT_OWNER, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "MuchoRoles: Only for contract owner or admin");
        _;
    }

    modifier onlyTraderOrAdmin(){
        require(hasRole(TRADER, msg.sender) || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "MuchoRoles: Only for trader or admin");
        _;
    }

    function changeProtocolOwner(address _newAdmin) public onlyAdmin{
        _protocolOwner = _newAdmin;
    }

}
