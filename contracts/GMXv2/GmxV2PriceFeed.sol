// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import '../../interfaces/GMXv2/IGmxV2PriceFeed.sol';
import '../MuchoRoles.sol';

contract GmxV2PriceFeed is IGmxV2PriceFeed, MuchoRoles {
    uint8 public decimals = 30;

    mapping(address => IChainLinkOracle) public chainLinkOracles;

    function setOracle(address _token, IChainLinkOracle _oracle) external onlyAdmin {
        chainLinkOracles[_token] = _oracle;
    }

    function hasOracle(address _token) external view returns (bool) {
        return address(chainLinkOracles[_token]) != address(0);
    }

    function getPrice(address _token) external view returns (uint256 price) {
        require(address(chainLinkOracles[_token]) != address(0), 'GmxV2PriceFeed: no oracle');
        int256 sPrice = chainLinkOracles[_token].latestAnswer();
        require(sPrice > 0, 'GmxV2PriceFeed: zero or negative price');

        price = uint256(sPrice);
        uint8 pDecimals = chainLinkOracles[_token].decimals();
        if (decimals > pDecimals) {
            price = price * 10 ** (decimals - pDecimals);
        } else if (decimals < pDecimals) {
            price = price / 10 ** (pDecimals - decimals);
        }
    }
}

interface IChainLinkOracle {
    function decimals() external view returns (uint8);

    function latestAnswer() external view returns (int256);
}
