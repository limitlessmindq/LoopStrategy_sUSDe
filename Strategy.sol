// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeERC20 } from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { MorphoLib } from "./libraries//MorphoLib.sol";
import { MorphoBalancesLib } from "./libraries/MorphoBalancesLib.sol";
import { MarketParamsLib } from "./libraries/MarketParamsLib.sol";
import { SharesMathLib } from "./libraries/SharesMathLib.sol";
import { Id, IMorpho, MarketParams } from "./interfaces/IMorpho.sol";
import { IUSDe } from "./interfaces/IUSDe.sol";
import { IStakedUSDe } from "./interfaces/IStakedUSDe.sol";
import { IUniswapV3Router } from "./interfaces/IUniswapV3Router.sol";
import { IQuoter } from "./interfaces/IQuoter.sol";


contract Strategy is Ownable {
    using MorphoLib for IMorpho;
    using MorphoBalancesLib for IMorpho;
    using MarketParamsLib for MarketParams;
    using SafeERC20 for IERC20;
    using SharesMathLib for uint256;

    IUSDe public constant USDe = IUSDe(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3);

    IStakedUSDe public constant StakedUSDe = IStakedUSDe(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);

    IERC20 public constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);

    IMorpho public morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    IUniswapV3Router public router = IUniswapV3Router(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    IQuoter public quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    constructor() Ownable(msg.sender) {}

    /*  Принцип работы стратегии доходности

        1. Вносим в стратегию USDe
        2. USDe вкладываем в Staking, и получаем sUSDe
        3. sUSDe вносим в Morpho в качестве collateral asset
        4. Берем в кредит USDT
        5. Свапаем USDT в USDe
        
        *Делаем несколько итераций 
    */

    function earn(uint256 interactions, uint256 deadline) external onlyOwner {

        for(uint256 i; i < interactions; i++) {
            uint256 USDeAmount = USDe.balanceOf(address(this));

            IERC4626(address(StakedUSDe)).deposit(USDeAmount, address(this));

            supplyCollateral(USDeAmount);

            borrow();

            swapUSDTtoUSDe(deadline);
        }
    }

    function exit() external onlyOwner {
        
    }

    /// @notice Handles the supply of collateral by the caller to a specific market.
    /// @param amount The amount of collateral the user is supplying.
    function supplyCollateral(uint256 amount) public {
        MarketParams memory marketParams = MarketParams(address(USDT), address(USDe), 0xE47E36457D0cF83A74AE1e45382B7A044f7abd99, 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC, 915000000000000000);

        IERC20(marketParams.collateralToken).forceApprove(address(morpho), type(uint256).max);

        address onBehalf = msg.sender;

        morpho.supplyCollateral(marketParams, amount, onBehalf, hex"");
    }

    /// @notice Handles the withdrawal of collateral by the caller from a specific market of a specific amount.
    /// @param amount The amount of collateral the user is withdrawing.
    function withdrawCollateral(uint256 amount) external {
        MarketParams memory marketParams = MarketParams(address(USDT), address(USDe), 0xE47E36457D0cF83A74AE1e45382B7A044f7abd99, 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC, 915000000000000000);

        address onBehalf = msg.sender;
        address receiver = msg.sender;

        morpho.withdrawCollateral(marketParams, amount, onBehalf, receiver);
    }

    /// @notice Handles the borrowing of assets by the caller from a specific market.
    /// @param amount The amount of assets the user is borrowing.
    /// @return assetsBorrowed The actual amount of assets borrowed.
    /// @return sharesBorrowed The shares borrowed in return for the assets.
    function borrow(uint256 amount)
        public
        returns (uint256 assetsBorrowed, uint256 sharesBorrowed)
    {
        uint256 shares;
        address onBehalf = msg.sender;
        address receiver = msg.sender;

        MarketParams memory marketParams = MarketParams(address(USDT), address(USDe), 0xE47E36457D0cF83A74AE1e45382B7A044f7abd99, 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC, 915000000000000000);

        (assetsBorrowed, sharesBorrowed) = morpho.borrow(marketParams, amount, shares, onBehalf, receiver);
    }

    /// @notice Handles the repayment of a specified amount of assets by the caller to a specific market.
    /// @param amount The amount of assets the user is repaying.
    /// @return assetsRepaid The actual amount of assets repaid.
    /// @return sharesRepaid The shares repaid in return for the assets.
    function repayAmount(uint256 amount)
        external
        returns (uint256 assetsRepaid, uint256 sharesRepaid)
    {   
        MarketParams memory marketParams = MarketParams(address(USDT), address(USDe), 0xE47E36457D0cF83A74AE1e45382B7A044f7abd99, 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC, 915000000000000000);

        IERC20(marketParams.loanToken).forceApprove(address(morpho), type(uint256).max);
        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 shares;
        address onBehalf = msg.sender;
        (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, shares, onBehalf, hex"");
    }

    /// @notice Handles the repayment of all the borrowed assets by the caller to a specific market.
    /// @return assetsRepaid The actual amount of assets repaid.
    /// @return sharesRepaid The shares repaid in return for the assets.
    function repayAll() external returns (uint256 assetsRepaid, uint256 sharesRepaid) {
        MarketParams memory marketParams = MarketParams(address(USDT), address(USDe), 0xE47E36457D0cF83A74AE1e45382B7A044f7abd99, 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC, 915000000000000000);
        
        IERC20(marketParams.loanToken).forceApprove(address(morpho), type(uint256).max);

        Id marketId = marketParams.id();

        (,, uint256 totalBorrowAssets, uint256 totalBorrowShares) = morpho.expectedMarketBalances(marketParams);
        uint256 borrowShares = morpho.position(marketId, msg.sender).borrowShares;

        uint256 repaidAmount = borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);
        IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), repaidAmount);

        uint256 amount;
        address onBehalf = msg.sender;
        (assetsRepaid, sharesRepaid) = morpho.repay(marketParams, amount, borrowShares, onBehalf, hex"");
    }

    function swapUSDTtoUSDe(uint256 _deadline) public returns(uint256) {
        uint256 _amountIn = USDT.balanceOf(address(this));

        uint256 _amountOutMinimum = quoter.quoteExactInputSingle(address(USDT), address(USDe), 10000, _amountIn, 0);

        uint256 amountOut = router.exactInputSingle(
            IUniswapV3Router.ExactInputSingleParams({
                tokenIn: address(USDT),
                tokenOut: address(USDe),
                fee: 10000,
                recipient: address(this),
                deadline: _deadline,
                amountIn: _amountIn,
                amountOutMinimum: _amountOutMinimum,
                sqrtPriceLimitX96: 0
            }) 
        ); 

        return amountOut;
    }

    // function getBalanceStakedUSDe() external view returns(uint256) {
    //     return StakedUSDe.balanceOf(address(this));
    // }

    // function getBalanceUSDe() external view returns(uint256) {
    //     return USDe.balanceOf(address(this));
    // }
}
