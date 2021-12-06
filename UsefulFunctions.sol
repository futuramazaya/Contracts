// SPDX-License-Identifier: MIT
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

pragma solidity ^0.8.10;

contract UsefulFunctions is Ownable{

    using SafeMath for uint256;

    struct BuyFee {
        uint16 liquidityFee;
        uint16 marketingFee;
        uint16 devFee;
        uint16 lotteryFee;
    }

    struct SellFee {
        uint16 liquidityFee;
        uint16 marketingFee;
        uint16 devFee;
        uint16 lotteryFee;
    }

    BuyFee public buyFee;
    SellFee public sellFee;
    uint16 private totalBuyFee;
    uint16 private totalSellFee;

    bool public isTradingEnabled;

    mapping(address => bool) public automatedMarketMakerPairs;
    mapping(address => bool) public _isBlackListed;

    IUniswapV2Router02 private router =
        IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3); 

    uint256 public maxBuyAmount = 1 * 10**7 * 10**18;
    uint256 public maxSellAmount = 1 * 10**7 * 10**18;
    uint256 public maxWalletAmount = 1 * 10**8 * 10**18;

    constructor() {
        buyFee.liquidityFee = 20;
        buyFee.marketingFee = 10;
        buyFee.devFee = 10;
        buyFee.lotteryFee = 20;
        totalBuyFee = 60;

        sellFee.liquidityFee = 30;
        sellFee.marketingFee = 15;
        sellFee.devFee = 15;
        sellFee.lotteryFee = 30;
        totalSellFee = 90;
    }

    function claimStuckTokens(address _token) external onlyOwner {
        require(_token != address(this), "No rugs");
        if (_token == address(0x0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }
        IERC20 erc20token = IERC20(_token);
        uint256 balance = erc20token.balanceOf(address(this));
        erc20token.transfer(owner(), balance);
    }

    function setBlackList(address addr, bool value) external onlyOwner {
        _isBlackListed[addr] = value;
    }

    function enableTrading() external onlyOwner {
        isTradingEnabled = true;
    }

    function setSellFee(
        uint16 lottery,
        uint16 marketing,
        uint16 liquidity,
        uint16 dev
    ) external onlyOwner {
        sellFee.lotteryFee = lottery;
        sellFee.marketingFee = marketing;
        sellFee.liquidityFee = liquidity;
        sellFee.devFee = dev;
        totalSellFee = lottery + marketing + liquidity + dev;
    }

    function setBuyFee(
        uint16 lottery,
        uint16 marketing,
        uint16 liquidity,
        uint16 dev
    ) external onlyOwner {
        buyFee.lotteryFee = lottery;
        buyFee.marketingFee = marketing;
        buyFee.liquidityFee = liquidity;
        buyFee.devFee = dev;
        totalBuyFee = lottery + marketing + liquidity + dev;
    }

    function setMaxWallet(uint256 value) external onlyOwner {
        maxWalletAmount = value;
    }

    function setMaxBuyAmount(uint256 value) external onlyOwner {
        maxBuyAmount = value;
    }

    function setMaxSellAmount(uint256 value) external onlyOwner {
        maxSellAmount = value;
    }
 

    function getTokenPrice(address _token, uint256 amount)
        internal
        view
        returns (uint256)
    {   
        address pairAddress = IUniswapV2Factory(router.factory()).getPair(router.WETH(),_token);

        IUniswapV2Pair pair = IUniswapV2Pair(pairAddress);
        (uint256 Res0, uint256 Res1, ) = pair.getReserves();

        return ((amount * Res0) / Res1); // return amount of token0 needed to buy token1
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal view {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isBlackListed[from] && !_isBlackListed[to],"Account is blacklisted");

        bool takeFee;

        if (takeFee) {
            require(isTradingEnabled,"Trading not enabled yet");

            if (!automatedMarketMakerPairs[to]) {
                require(
                    balanceOf(to) + amount <= maxWalletAmount,
                    "Balance exceeds limit"
                );
            }

            uint256 fees;

            if (automatedMarketMakerPairs[to]) {
                require(amount <= maxSellAmount, "Sell exceeds limit");
                fees = totalSellFee;
            } else if (automatedMarketMakerPairs[from]) {
                require(amount <= maxBuyAmount, "Buy exceeds limit");
                fees = totalBuyFee;
            }
            
            uint256 feeAmount = amount.mul(fees).div(1000);
            amount = amount.sub(feeAmount);
            super._transfer(from, address(this), feeAmount);
        }

    }
}
