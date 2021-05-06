//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


contract TokenLocker {


    address public _withdrawAddress;
    uint256 public _timeLimit = 7 days;
    uint256 public _unlockRate = 10;
    uint256 public _lastWithdraw = block.timestamp;
    event Withdraw(uint256 amount, uint256 timestamp);

    modifier onlyWithdrawAddress () {
        require(msg.sender == _withdrawAddress);
        _;
    }

    constructor (address withdraw) {
        _withdrawAddress = withdraw;
    }
    
    function setWithdrawAddress(address withdraw) external onlyWithdrawAddress{
        _withdrawAddress = withdraw;
    }

    function withdrawTokens(IBEP20 token) onlyWithdrawAddress external {
        uint256 contractBalance = token.balanceOf(address(this));
        require(block.timestamp - _lastWithdraw >= _timeLimit,"Timelimit not yet reached");
        require(contractBalance > 0,"Insufficient funds");
        uint256 multiplier = (block.timestamp - _lastWithdraw) / _timeLimit;
        uint256 amount = (contractBalance * multiplier * _unlockRate) / 100;
        uint256 withdrawable = amount > contractBalance ? contractBalance : amount;
        token.transfer(_withdrawAddress,withdrawable);
        _lastWithdraw = block.timestamp;
        emit Withdraw(amount,block.timestamp);

    }

}
