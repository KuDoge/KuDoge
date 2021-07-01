// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

//oz libaries
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./IKoffeeSwapRouter.sol";
import "./IKoffeeSwapFactory.sol";


contract KuDoge is ERC20, Ownable {
    using Address for address;
    
    //Mainnet router 0xc0fFee0000C824D24E0F280f1e4D21152625742b
    IKoffeeSwapRouter public router;
    address public pair;
    
    bool private _liquidityMutex = false;
    uint256 public _tokenLiquidityThreshold = 5000000e18;
    bool public ProvidingLiquidity = false;
   
    uint16 public feeliq = 60;
    uint16 public feeburn = 20;
    uint16 public feedev = 10;
    uint16 constant internal DIV = 1000;
    
    uint16 public feesum = feeliq + feeburn + feedev;
    uint16 public feesum_ex = feeliq + feedev;
    
    address payable public devwallet = payable(0xbBa2FA1d6FCA5A6A28DC6E5D27ECE24494BC24e6);

    uint256 public transferlimit;

    mapping (address => bool) public exemptTransferlimit;    
    mapping (address => bool) public exemptFee; 
    
    event LiquidityProvided(uint256 tokenAmount, uint256 nativeAmount, uint256 exchangeAmount);
    event LiquidityProvisionStateChanged(bool newState);
    event LiquidityThresholdUpdated(uint256 newThreshold);
    
    
    modifier mutexLock() {
        if (!_liquidityMutex) {
            _liquidityMutex = true;
            _;
            _liquidityMutex = false;
        }
    }
    
    constructor() ERC20("KuDoge", "KuDo") {
        _mint(msg.sender, 1e15 * 10 ** decimals());      
        transferlimit = 5e12 * 10 ** decimals();
        exemptTransferlimit[msg.sender] = true;
        exemptFee[msg.sender] = true;

        exemptTransferlimit[devwallet] = true;
        exemptFee[devwallet] = true;

        exemptTransferlimit[address(this)] = true;
        exemptFee[address(this)] = true;
    }
   
    
    function _transfer(address sender, address recipient, uint256 amount) internal override {        

        //check transferlimit
        require(amount <= transferlimit || exemptTransferlimit[sender] || exemptTransferlimit[recipient] , "you can't transfer that much");

        //calculate fee        
        uint256 fee_ex   = amount * feesum_ex / DIV;
        uint256 fee_burn = amount * feeburn / DIV;

        uint256 fee = fee_ex + fee_burn;
        
        //set fee to zero if fees in contract are handled or exempted
        if (_liquidityMutex || exemptFee[sender] || exemptFee[recipient]) fee = 0;

        //send fees if threshhold has been reached
        //don't do this on buys, breaks swap
        if (ProvidingLiquidity && sender != pair) handle_fees();      
        
        //rest to recipient
        super._transfer(sender, recipient, amount - fee);
        
        //send the fee to the contract
        if (fee > 0) {
            super._transfer(sender, address(this), fee_ex);   
            _burn(sender, fee_burn);
        }      
    }
    
    
    function handle_fees() private mutexLock {
        uint256 contractBalance = balanceOf(address(this));
        if (contractBalance >= _tokenLiquidityThreshold) {
            contractBalance = _tokenLiquidityThreshold;
            
            //calculate how many tokens we need to exchange
            uint256 exchangeAmount = contractBalance / 2;
            uint256 exchangeAmountOtherHalf = contractBalance - exchangeAmount;

            //exchange to KCS
            exchangeTokenToNativeCurrency(exchangeAmount);
            uint256 kcs = address(this).balance;
            
            uint256 KCS_dev = kcs * feedev / feesum_ex;
            
            //send KCS to dev
            sendKCSToDev(KCS_dev);
            
            //add liquidity
            addToLiquidityPool(exchangeAmountOtherHalf, kcs - KCS_dev);
            
        }
    }

    function exchangeTokenToNativeCurrency(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WKCS();

        _approve(address(this), address(router), tokenAmount);
        router.swapExactTokensForKCSSupportingFeeOnTransferTokens(tokenAmount, 0, path, address(this), block.timestamp);
    }

    function addToLiquidityPool(uint256 tokenAmount, uint256 nativeAmount) private {
        _approve(address(this), address(router), tokenAmount);
        //provide liquidity and send lP tokens to zero
        router.addLiquidityKCS{value: nativeAmount}(address(this), tokenAmount, 0, 0, address(this), block.timestamp);
    }    
    
    function setRouterAddress(address newRouter) external onlyOwner {
        //give the option to change the router down the line 
        IKoffeeSwapRouter _newRouter = IKoffeeSwapRouter(newRouter);
        address get_pair = IKoffeeSwapFactory(_newRouter.factory()).getPair(address(this), _newRouter.WKCS());
        //checks if pair already exists
        if (get_pair == address(0)) {
            pair = IKoffeeSwapFactory(_newRouter.factory()).createPair(address(this), _newRouter.WKCS());
        }
        else {
            pair = get_pair;
        }
        router = _newRouter;
    }    
    
    function sendKCSToDev(uint256 amount) private {
        //transfers KCS out of contract to devwallet
        devwallet.transfer(amount);
    }
    
    function changeLiquidityProvide(bool state) external onlyOwner {
        //change liquidity providing state
        ProvidingLiquidity = state;
        emit LiquidityProvisionStateChanged(state);
    }
    
    function changeLiquidityTreshhold(uint256 new_amount) external onlyOwner {
        //change the treshhold
        _tokenLiquidityThreshold = new_amount;
        emit LiquidityThresholdUpdated(new_amount);
    }   
    
    function changeFees(uint16 _feeliq, uint16 _feeburn, uint16 _feedev) external onlyOwner returns (bool){
        feeliq = _feeliq;
        feeburn = _feeburn;
        feedev = _feedev;
        feesum = feeliq + feeburn + feedev;
        feesum_ex = feeliq + feedev;
        require(feesum <= 100, "exceeds hardcap");
        return true;
    }

    function changeTransferlimit(uint256 _transferlimit) external onlyOwner returns (bool) {
        transferlimit = _transferlimit;
        return true;
    }

    function updateExemptTransferLimit(address _address, bool state) external onlyOwner returns (bool) {
        exemptTransferlimit[_address] = state;
        return true;
    }

    function updateExemptFee(address _address, bool state) external onlyOwner returns (bool) {
        exemptFee[_address] = state;
        return true;
    }

    function updateDevwallet(address _address) external onlyOwner returns (bool){
        devwallet = payable(_address);
        exemptTransferlimit[devwallet] = true;
        exemptFee[devwallet] = true;
        return true;
    }
    
    // fallbacks
    receive() external payable {}
    
}