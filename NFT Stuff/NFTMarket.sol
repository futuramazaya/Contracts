// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;


import "@openzeppelin/contracts/interfaces/IERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract NFTMarket is Ownable {

    struct Order{
        IERC721 nftContract;
        uint256 tokenId;
        address orderCreator;
        uint256 price;
    }

    mapping(uint256 => Order) public orders;
    mapping(address => mapping(uint256 => uint256)) public nftToOrderId;

    uint256 public totalOrders;

    uint256 public feePercent = 20; //2% fee

    event OrderCreated(address nftContract,uint256 tokenId, uint256 orderId);
    event OrderProcessed(uint256 orderId,address buyer,address contractAdd ,uint256 tokenId, uint256 price);

    function list(address _contractAdd, uint256 _tokenId, uint256 _price) external {
        IERC721 nftAdd = IERC721(_contractAdd);
        nftAdd.transferFrom(msg.sender, address(this), _tokenId);

        orders[totalOrders].nftContract = nftAdd;
        orders[totalOrders].tokenId = _tokenId;
        orders[totalOrders].orderCreator = msg.sender;
        orders[totalOrders].price = _price;

        nftToOrderId[_contractAdd][_tokenId] = totalOrders;
        emit OrderCreated(_contractAdd,_tokenId,totalOrders);

        totalOrders++;
    }

    function deList(uint256 orderId) external {
        require(msg.sender == orders[orderId].orderCreator,"Not allowed");

        IERC721 nftAdd = IERC721(orders[orderId].nftContract);
        nftAdd.transferFrom(address(this), msg.sender, orders[orderId].tokenId);

        delete nftToOrderId[address(nftAdd)][orders[orderId].tokenId];
        delete orders[orderId];
    }

    function buyWithOrderId(uint256 orderId) public payable {
        Order memory order = orders[orderId];
        IERC721 nftAdd = IERC721(order.nftContract);

        require(address(order.nftContract) != address(0),"Invalid order Id");
        require(msg.value >= order.price,"Not enough ETH to buy");

        uint256 feeAmount = msg.value * feePercent / 1000;
        payable(owner()).transfer(feeAmount);
        payable(order.orderCreator).transfer(msg.value - feeAmount);

        nftAdd.transferFrom(address(this), msg.sender, order.tokenId);

        emit OrderProcessed(orderId,msg.sender,address(order.nftContract),order.tokenId,msg.value);

        delete orders[orderId];
        delete nftToOrderId[address(nftAdd)][orders[orderId].tokenId];
    }

    function buyWithContractAddress(address contractAdd, uint256 id) public payable {
        uint256 Id = nftToOrderId[contractAdd][id];
        require(Id != 0,"Invalid order");

        buyWithOrderId(Id);
    }
}
