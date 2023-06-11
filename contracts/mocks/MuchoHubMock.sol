// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../../interfaces/IMuchoHub.sol";
import "../../interfaces/IPriceFeed.sol";
import "hardhat/console.sol";

contract MuchoHubMock is IMuchoHub{
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    int256 apr = 10000;
    mapping(address => uint256) lastUpdate;
    mapping(address => uint256) tokenAmount;
    EnumerableSet.AddressSet tokenList;
    IPriceFeed priceFeed;

    function setApr(int256 _apr) external{
        apr = _apr;
    }

    function depositFrom(address _investor, address _token, uint256 _amount) external{
        tokenList.add(_token);
        tokenAmount[_token] = tokenAmount[_token].add(_amount);
        IERC20(_token).safeTransferFrom(_investor, address(this), _amount);
        //console.log("    SOL - Transferring", _amount);
        if(lastUpdate[_token] == 0){
            //console.log("    SOL - Updating last updated", block.timestamp);
            lastUpdate[_token] = block.timestamp;
        }
    }
    function withdrawFrom(address _investor, address _token, uint256 _amount) external{
        tokenAmount[_token] = tokenAmount[_token].sub(_amount);
        if(lastUpdate[_token] == 0){
            console.log("    SOL - Updating last update", block.timestamp);
            lastUpdate[_token] = block.timestamp;
        }
        IERC20(_token).safeTransfer(_investor, _amount);
    }

    function addProtocol(address _contract) external{}
    function removeProtocol(address _contract) external{}

    function moveInvestment(address _token, uint256 _amount, address _protocolSource, address _protocolDestination) external{}
    function setDefaultInvestment(address _token, InvestmentPart[] calldata _partitionList) external{}

    function refreshInvestment(address _protocol) external{ }
    function refreshAllInvestments() public{
        for(uint i = 0; i < tokenList.length(); i++){
            address token = tokenList.at(i);
            uint256 absApr = apr>0?uint256(apr):uint256(-apr);
            /*console.log("    ***************SOL - Refreshing token*****************", i);
            console.log("    SOL - Previous amount", tokenAmount[token]);
            console.log("    SOL - Abs Apr", absApr);
            console.log("    SOL - Timestamp", block.timestamp);
            console.log("    SOL - Timediff", block.timestamp.sub(lastUpdate[token]));
            console.log("    SOL - 1 year", 365 days);*/

            uint256 earn = tokenAmount[token].mul(absApr).mul(block.timestamp.sub(lastUpdate[token])).div(365 days).div(10000);
            //console.log("    SOL - earn", earn);
            if(apr < 0){
                if(earn > tokenAmount[token])
                    tokenAmount[token] = 0;
                else
                    tokenAmount[token] = tokenAmount[token].sub(earn);
            }
            else{
                tokenAmount[token] = tokenAmount[token].add(earn);
            }

            lastUpdate[token] = block.timestamp;
        }
    }

    function getTotalNotInvested(address _token) external pure returns(uint256){
        return 0;
    }
    function getTotalStaked(address _token) external view returns(uint256){
        return tokenAmount[_token];
    }

    function getTotalUSD() external view returns(uint256){
        uint256 total;
        
        for(uint i = 0; i < tokenList.length(); i++){
            IERC20Metadata token = IERC20Metadata(tokenList.at(i));
            uint8 decimalsAdjust = 30 + token.decimals() - 18;
            uint256 usd = token.balanceOf(address(this)).mul(priceFeed.getPrice(address(token))).div(10**decimalsAdjust);
            total = total.add(usd);
        }

        return total;
    }

    function getProtocols() external view returns(address[] memory){
        address[] memory list = new address[](1);
        list[0] = address(this);
        return list;
    }
    
    function getDefaultInvestment(address _token) external view returns(InvestmentPartition memory){
        InvestmentPart memory part = InvestmentPart({protocol: address(this), percentage:10000});
        InvestmentPart[] memory parts = new InvestmentPart[](1);
        parts[0] = part;
        return InvestmentPartition({defined: true, parts: parts});
    }
    
    function getCurrentInvestment(address _token) external view returns(InvestmentAmountPartition memory){
        InvestmentAmountPart[] memory parts = new InvestmentAmountPart[](1);
        parts[0].protocol = address(this);
        parts[0].amount = tokenAmount[_token];
        InvestmentAmountPartition memory out = InvestmentAmountPartition({parts: parts});
        return out;
    }
}