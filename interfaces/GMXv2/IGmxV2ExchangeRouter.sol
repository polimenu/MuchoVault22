// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

interface IGmxV2ExchangeRouter {
    function createDeposit(address account, DepositUtils.CreateDepositParams calldata params) external returns (bytes32);

    function createWithdrawal(address account, WithdrawalUtils.CreateWithdrawalParams calldata params) external returns (bytes32);

    function sendTokens(address token, address receiver, uint256 amount) external;

    function sendWnt(address receiver, uint256 amount) external;
}

library DepositUtils {
    struct CreateDepositParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address initialLongToken;
        address initialShortToken;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minMarketTokens;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }
}

library WithdrawalUtils {
    struct CreateWithdrawalParams {
        address receiver;
        address callbackContract;
        address uiFeeReceiver;
        address market;
        address[] longTokenSwapPath;
        address[] shortTokenSwapPath;
        uint256 minLongTokenAmount;
        uint256 minShortTokenAmount;
        bool shouldUnwrapNativeToken;
        uint256 executionFee;
        uint256 callbackGasLimit;
    }
}
