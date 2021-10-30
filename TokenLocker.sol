//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract TokenLocker is Ownable {

    IERC20 public token;

    struct User{
        bool active;
        bool isWhitelisted;
        uint256 depositTime;
        uint256 depositAmount;
        uint256 releaseTime;
        uint256 lockTime;
    }

    mapping(address => User) public users;
    mapping(uint256 => uint256) public lockTimeToReward;

    event Deposit(address user, uint256 amount, uint256 lockTime);
    event Withdraw(address user, uint256 reward, uint256 lockTime);

    constructor (address _token) {
        token = IERC20(_token);
        lockTimeToReward[4 weeks] = 50;
        lockTimeToReward[8 weeks] = 100;
        lockTimeToReward[16 weeks] = 200;
    }

    function setLockRewards(uint256 lockTime, uint256 reward) external onlyOwner {
        lockTimeToReward[lockTime] = reward;
    }

    function setWhitelist(address user, bool value) external onlyOwner {
        users[user].isWhitelisted = value;
    }

    function deposit(uint256 lockTime, uint256 amount) external {
        User storage user = users[msg.sender];

        require(!user.active,"Deposit already exists");
        require(user.isWhitelisted,"User not whitelisted");

        token.transferFrom(msg.sender, address(this), amount);

        user.active = true;
        user.depositTime = block.timestamp;
        user.depositAmount = amount;
        user.releaseTime = block.timestamp + lockTime;
        user.lockTime = lockTime;

        emit Deposit(msg.sender,amount,lockTime);
    }

    function withdraw() external {
        User storage user = users[msg.sender];

        require(user.active,"User have no deposits");
        require(block.timestamp >= user.releaseTime ,"Token still in locked state");
        
        uint256 reward = user.depositAmount * lockTimeToReward[user.lockTime] / 1000;
        uint256 withdrawAmount = reward + user.depositAmount;

        require(token.balanceOf(address(this)) >= withdrawAmount,"Not enough balance to pay reward");

        user.depositAmount = 0;
        user.active = false;

        token.transfer(msg.sender, withdrawAmount);

        emit Withdraw(msg.sender,withdrawAmount, user.lockTime);
    }

}