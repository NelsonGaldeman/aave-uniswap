// SPDX-License-Identifier: MIT License
pragma solidity >=0.6.6 <0.6.12;

import "./interfaces/IERC20.sol";
import "./libraries/SafeERC20.sol";
import "./interfaces/aave/ILendingPool.sol";
import "./interfaces/aave/IProtocolDataProvider.sol";
import "./interfaces/aave/ILendingPoolAddressesProvider.sol";
import "./interfaces/uniswap/IUniswapV2Pair.sol";
import "./interfaces/uniswap/IUniswapV2Factory.sol";
import "./interfaces/uniswap/IUniswapV2Router01.sol";
import "./interfaces/uniswap/IUniswapV2Router02.sol";

contract AaveeUniswap {
    using SafeERC20 for IERC20;

    /* ============ Immutable State Variables ============ */
    
    ILendingPool public immutable AAVE_LENDING_POOL;
    IProtocolDataProvider public immutable AAVE_DATA_PROVIDER;
    IUniswapV2Router02 public immutable UNIV2_ROUTER;
    IUniswapV2Factory public immutable UNIV2_FACTORY;
    
    /* ============ Events ============ */
    
    event Received(address, uint256);

    /* ============ Constructor ============ */
    
    /**
     * @param aaveProvider          Aave pool addresses provider, used to fetch the lending pool contract
     * @param aaveDataProvider      Aave data provider, used to get aToken addreses
     * @param uniRouter             Uniswap v2 router
     */
    constructor(
        ILendingPoolAddressesProvider aaveProvider, 
        IProtocolDataProvider aaveDataProvider, 
        IUniswapV2Router02 uniRouter
    ) public {
        // Initialize the lending pool from the provider proxy
        AAVE_LENDING_POOL = ILendingPool(aaveProvider.getLendingPool());
        
        // Save AAVE v2 data provider
        AAVE_DATA_PROVIDER = aaveDataProvider;
        
        // Save Uniswap v2 router
        UNIV2_ROUTER = uniRouter;
        
        // Save Uniswap v2 factory
        UNIV2_FACTORY = IUniswapV2Factory(uniRouter.factory());
    }
    
    /* ============ External functions ============ */
    
    /**
     * Takes your assets, deposits on Aave and sends back the aTokens to the caller's account
     * 
     * @param asset     The address of the token to deposit
     * @param amount    The amount to deposit
     */
    function aaveDeposit(address asset, uint256 amount) external {
        // Make sure the token has been approved to be spent
        require(IERC20(asset).allowance(msg.sender, address(this)) >= amount, "TOKEN_NOT_APPROVED");
        
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        executeAaveDeposit(asset, amount);
    }
    
    /**
     * Withdraws a token from Aave and sends it back to the wallet
     * Note: The asset addres must be the original one, not the aToken
     * 
     * @param asset     The address of the token to withdraw
     * @param amount    The withdrawal amount
     */
    function aaveWithdraw(address asset, uint256 amount) external {
        executeAaveWithdraw(asset, amount, true);
    }
    
    /**
     * Moves full amount of a token from Aave to a Uniswap liquidity pool
     * Note: You must provide the necesary amount of ETH to send to the pool
     * 
     * @param asset     The address of the token is being moved
     * @param deadline  Timestamp - if reached before the liquidity is provided will revert
     */
    function moveAllAaveToUniswap(address asset, uint256 deadline) payable external {
        // Gets the aToken of the asset provided
        (address aTokenAddress,,) = AAVE_DATA_PROVIDER.getReserveTokensAddresses(asset);
        
        uint256 amount = IERC20(aTokenAddress).balanceOf(msg.sender);
        moveAaveToUniswap(asset, amount, deadline);
    }
    
    /**
     * Moves the full amount of a token from Uniswap liquidity pool to Aave
     * Note: DOESN'T WORK - coudln't figure out the error after a reasonable amount of time
     * It should be something silly...
     * 
     * @param asset     The address of the token is being moved (not the pool token, the actual asset)
     * @param deadline  Timestamp - if reached before the liquidity is provided will revert
     */
    function moveAllUniswapToAave(address asset, uint256 deadline) external {
        IUniswapV2Pair uniPool = IUniswapV2Pair(UNIV2_FACTORY.getPair(asset, UNIV2_ROUTER.WETH()));
        require(address(uniPool) != address(0), "UNKNOWN_POOL");
        
        uint256 amount = uniPool.balanceOf(msg.sender);
        moveUniswapToAave(asset, amount, deadline);
    }
    
    /* ============ Public functions ============ */
    
    /**
     * Moves a specific amount of a token from Aave to a Uniswap liquidity pool
     * Note: You must provide the necesary amount of ETH to send to the pool
     * 
     * @param asset     The address of the token is being moved
     * @param amount    The amount to be moved
     * @param deadline  Timestamp - if reached before the liquidity is provided will revert
     */
    function moveAaveToUniswap(address asset, uint256 amount, uint256 deadline) payable public {
        executeAaveWithdraw(asset, amount, false);
        IERC20(asset).safeApprove(address(UNIV2_ROUTER), amount);
        
        // Minimum values are set to zero for simplicity
        UNIV2_ROUTER.addLiquidityETH{ value: msg.value }(
            asset, 
            amount, 
            0,
            0,
            msg.sender, 
            deadline
        );
        
        // Send ETH back to user's wallet
        if (address(this).balance > 0) {
            msg.sender.transfer(address(this).balance);
        }
    }
    
    /**
     * Moves a specific amount of a token from Uniswap liquidity pool to Aave
     * Note: DOESN'T WORK - coudln't figure out the error after a reasonable amount of time
     * It should be something silly...
     * 
     * @param asset     The address of the token is being moved (not the pool token, the actual asset)
     * @param amount    The amount to be moved
     * @param deadline  Timestamp - if reached before the liquidity is provided will revert
     */
    function moveUniswapToAave(address asset, uint256 amount, uint256 deadline) public {
        IUniswapV2Pair uniPool = IUniswapV2Pair(UNIV2_FACTORY.getPair(asset, UNIV2_ROUTER.WETH()));
        require(address(uniPool) != address(0), "UNKNOWN_POOL");
        
        // Make sure the token has been approved to be spent
        require(uniPool.allowance(msg.sender, address(this)) >= amount, "TOKEN_NOT_APPROVED");
        
        if (!uniPool.transferFrom(msg.sender, address(this), amount)) {
            revert("UNI_TRANSFER_FAILED");
        }
        
        if (!uniPool.approve(address(UNIV2_ROUTER), amount)) {
            revert("UNI_APPROVAL_FAILED");
        }
        
        // Minimum values are set to zero for simplicity
        (uint256 amountToken, uint256 amountEth) = UNIV2_ROUTER.removeLiquidityETH(
            address(uniPool),
            amount, 
            0,
            0,
            address(this),
            deadline
        );
        
        require(amountToken > 0, "UNI_NO_TOKENS_BACK");
        
        // Send ETH back to user's wallet
        if (amountEth > 0) {
            msg.sender.transfer(amountEth);
        }
        
        executeAaveDeposit(asset, amountToken);
    }
    
    /* ============ Internal functions ============ */
    
    /**
     * Executes the Aave deposit
     * 
     * @param asset     The address of the token
     * @param amount    The amount to be deposited
     */
    function executeAaveDeposit(address asset, uint256 amount) internal {
        IERC20(asset).safeApprove(address(AAVE_LENDING_POOL), amount);
        AAVE_LENDING_POOL.deposit(asset, amount, msg.sender, 0);
    }
    
    /**
     * Executes the Aave withdrawal
     * 
     * @param asset             The address of the token
     * @param amount            The amount to be deposited
     * @param fundsToWallet     When true, funds are going to caller's account. Otherwise funds stay in the contract
     */
    function executeAaveWithdraw(address asset, uint256 amount, bool fundsToWallet) internal {
        // Gets the aToken of the asset provided
        (address aTokenAddress,,) = AAVE_DATA_PROVIDER.getReserveTokensAddresses(asset);
        
        require(IERC20(aTokenAddress).allowance(msg.sender, address(this)) >= amount, "TOKEN_NOT_APPROVED");
        IERC20(aTokenAddress).safeTransferFrom(msg.sender, address(this), amount);
        
        // Withdraws the asset from AAVE and sents it back to user's wallet or keeps it in the contract (depends on fundsToWallet bool)      
        AAVE_LENDING_POOL.withdraw(asset, amount, fundsToWallet ? msg.sender : address(this));
    }
    
    /**
     * Receives ETH transfers and emits an event
     */
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }
}
//"0x88757f2f99175387ab4c6a4b3067c77a695b0349","0x3c73A5E5785cAC854D468F727c606C07488a29D6","0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D"
//"0xFf795577d9AC8bD7D90Ee22b6C1703490b6512FD","1632233921"