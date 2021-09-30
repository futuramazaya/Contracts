// SPDX-License-Identifier: MIT

pragma solidity ^0.8.6;


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract HotelCalifornia is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 private uniswapV2Router;
    address public uniswapV2Pair;

    struct BuyFee{
        uint16 liquidityFee;
        uint16 marketingFee;
    }

    struct SellFee{
        uint16 liquidityFee;
        uint16 marketingFee;
    }

    BuyFee public buyFee;
    SellFee public sellFee;

    bool private swapping;
    bool private isTradingEnabled;
    bool public swapEnabled;

    address private constant deadWallet = address(0xdead);

    uint256 public swapTokensAtAmount = 1 * 10**8 * (10**18);
    uint256 public AntiWhale = 1 * 10**9 * (10**18);

    uint16 private totalBuyFee;
    uint16 private totalSellFee;

    address public _marketingWalletAddress = address(0x123); //Change here

     // exlcude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;


    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event SwapAndSend(
        uint256 liquidityToken,
        uint256 marketingToken,
        uint256 liquidityBNB
    );


    constructor() ERC20("Hotel California", "Cali") {

    	IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
         // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        buyFee.liquidityFee = 30;
        buyFee.marketingFee = 50;
        totalBuyFee = buyFee.liquidityFee + buyFee.marketingFee;

        sellFee.liquidityFee = 30;
        sellFee.marketingFee = 70;
        totalSellFee = sellFee.liquidityFee + sellFee.marketingFee;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(_marketingWalletAddress, true);
        excludeFromFees(address(this), true);

        swapEnabled = true;

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(owner(), 1 * 10**12 * (10**18));
    }

    receive() external payable {

  	}

    function updateUniswapV2Router(address newAddress) external onlyOwner {
        require(newAddress != address(uniswapV2Router), "CALI: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function setSwapTokensAmt(uint256 amt) external onlyOwner{
        swapTokensAtAmount = amt;
    }

    function setWhaleAmt(uint256 amt) external onlyOwner{
        AntiWhale = amt;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "CALI: Account is already excluded");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    function setMarketingWallet(address payable wallet) external onlyOwner{
        _marketingWalletAddress = wallet;
    }

    function enableTrading() external onlyOwner{
        isTradingEnabled = true;
    }

    function setBuyFee(uint16 liqFee, uint16 marketing) external onlyOwner {
        buyFee.liquidityFee = liqFee;
        buyFee.marketingFee = marketing;
        totalBuyFee = buyFee.liquidityFee + buyFee.marketingFee;
    }

    function setSellFee(uint16 liqFee, uint16 marketing) external onlyOwner {
        sellFee.liquidityFee = liqFee;
        sellFee.marketingFee = marketing;
        totalSellFee = sellFee.liquidityFee + sellFee.marketingFee;
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "CALI: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }

    function setSwapEnabled(bool value) external onlyOwner{
        swapEnabled = value;
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "CALI: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        emit SetAutomatedMarketMakerPair(pair, value);
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

		uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if( canSwap &&
            !swapping &&
            swapEnabled &&
            !automatedMarketMakerPairs[from] &&
            from != owner() &&
            to != owner()
        ) {
            swapping = true;

            swapAndSend(contractTokenBalance);

            swapping = false;
        }

        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if(takeFee) {
            require(isTradingEnabled,"Trading not enabled yet");

            uint16 totalFee;

            if(!automatedMarketMakerPairs[to]){
                require(balanceOf(to)+amount <= AntiWhale, "you are crossing wallet limit" );
            }

            if(automatedMarketMakerPairs[from]){
                totalFee = totalBuyFee;
            }else if(automatedMarketMakerPairs[to]){
                totalFee = totalSellFee;
            }

        	uint256 fees = amount.mul(totalFee).div(1000);
            amount = amount.sub(fees);
            super._transfer(from, address(this), fees);

        }

        super._transfer(from, to, amount);

    }

    function swapAndSend(uint256 tokens) private {

        uint256 totalFees = totalBuyFee + totalSellFee;

        uint256 forLiquidity = tokens.mul(
            buyFee.liquidityFee + sellFee.liquidityFee).div(totalFees);

        uint256 forMarketing = tokens.mul(
            buyFee.marketingFee + sellFee.marketingFee).div(totalFees);    

        uint256 half = forLiquidity.div(2);

        // swap tokens for ETH
        swapTokensForEth(half + forMarketing); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        uint256 newBalance = address(this).balance;

        uint256 liquidityShare = newBalance.mul(forLiquidity).div(tokens);

        // add liquidity to uniswap
        addLiquidity(forLiquidity.div(2), liquidityShare);

        payable(_marketingWalletAddress).transfer(address(this).balance);

        emit SwapAndSend(forLiquidity, forMarketing, liquidityShare);
    }


    function swapTokensForEth(uint256 tokenAmount) private {


        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {

        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(0),
            block.timestamp
        );

    }
}