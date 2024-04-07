// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '../../interfaces/IMuchoProtocol.sol';
import '../../interfaces/IPriceFeed.sol';
import '../../interfaces/IMuchoToken.sol';
import '../MuchoRoles.sol';

contract MuchoProtocolUnbacked is IMuchoProtocol, MuchoRoles {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet tokenList;
    IPriceFeed priceFeed = IPriceFeed(0x846ecf0462981CC0f2674f14be6Da2056Fc16bDA);
    mapping(address => uint256) public unbackedAmount;

    function protocolName() public pure returns (string memory) {
        return 'MuchoProtocolUnbacked';
    }

    function protocolDescription() public pure returns (string memory) {
        return 'Represents the unbacked amount when MuchoProtocolGmx changed in 7th April 2024';
    }

    //CONSTRUCTOR
    constructor() {
        tokenList.add(0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        tokenList.add(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
        tokenList.add(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f);

        unbackedAmount[0x82aF49447D8a07e3bd95BD0d56f35241523fBab1] = 19.7767160 ether;
    }

    //METHODS
    function cycleRewards() public onlyOwnerTraderOrAdmin {}

    function refreshInvestment() external onlyOwnerTraderOrAdmin {}

    function setPriceFeed(IPriceFeed _feed) external onlyAdmin {
        priceFeed = _feed;
    }

    function setAmount(address _token, uint256 _amount) external onlyAdmin {
        unbackedAmount[_token] = _amount;
    }

    function withdrawAndSend(address _token, uint256 _amount, address _target) external onlyAdmin {
        IERC20 tk = IERC20(_token);
        require(tk.balanceOf(address(this)) >= _amount, 'MuchoProtocolUnbacked: not enough balance');
        tk.safeTransfer(_target, _amount);
    }

    function notInvestedTrySend(address _token, uint256 _amount, address _target) external onlyAdmin returns (uint256) {
        return 0;
    }

    function deposit(address _token, uint256 _amount) external onlyAdmin {}

    function setRewardPercentages(RewardSplit memory _split) external onlyAdmin {}

    function setCompoundProtocol(IMuchoProtocol _target) external onlyAdmin {}

    function setMuchoRewardRouter(address _contract) external onlyAdmin {}

    //VIEWS
    function getExpectedAPR(address _token, uint256 _additionalAmount) external pure returns (uint256) {
        return 0;
    }

    function getDepositFee(address _token, uint256 _amount) external pure returns (uint256) {
        return 0;
    }

    function getWithdrawalFee(address _token, uint256 _amount) external pure returns (uint256) {
        return 0;
    }

    function getExpectedNFTAnnualYield() external pure returns (uint256) {
        return 0;
    }

    function getTokenNotInvested(address _token) public view returns (uint256) {
        return unbackedAmount[_token];
    }

    function getTokenInvested(address _token) public pure returns (uint256) {
        return 0;
    }

    function getTokenStaked(address _token) public view returns (uint256) {
        return getTokenNotInvested(_token);
    }

    function getAllTokensStaked() public view returns (address[] memory, uint256[] memory) {
        address[] memory tkOut = new address[](tokenList.length());
        uint256[] memory amOut = new uint256[](tokenList.length());
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            tkOut[i] = tokenList.at(i);
            amOut[i] = getTokenStaked(tkOut[i]);
        }

        return (tkOut, amOut);
    }

    function getTokenUSDInvested(address _token) public view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return getTokenInvested(_token).mul(priceFeed.getPrice(_token)).div(10 ** (30 - 18 + decimals));
    }

    function getTokenUSDNotInvested(address _token) public view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return getTokenNotInvested(_token).mul(priceFeed.getPrice(_token)).div(10 ** (30 - 18 + decimals));
    }

    function getTokenUSDStaked(address _token) public view returns (uint256) {
        uint8 decimals = IERC20Metadata(_token).decimals();
        return getTokenStaked(_token).mul(priceFeed.getPrice(_token)).div(10 ** (30 - 18 + decimals));
    }

    function getTotalUSD() external view returns (uint256) {
        uint256 totalUsd = 0;
        for (uint256 i = 0; i < tokenList.length(); i = i.add(1)) {
            uint8 decimalsAdjust = 30 - 18 + IERC20Metadata(tokenList.at(i)).decimals();
            totalUsd = totalUsd.add(
                IERC20(tokenList.at(i)).balanceOf(address(this)).mul(priceFeed.getPrice(tokenList.at(i))).div(10 ** decimalsAdjust)
            );
        }
        return totalUsd;
    }
}
