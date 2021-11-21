// SPDX-License-Identifier: MIT

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC721 is Context, ERC165, IERC721, IERC721Metadata, Ownable {
    using Address for address;
    using Strings for uint256;
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    struct Auction {
        uint256 id;
        uint256 startTime;
        uint256 endTime;
        uint256 tokenId;
        uint256 minBidPrice;
        address tokenAddress;
        string creatorName;
        address creatorAddress;
        address auctionCreator;
        bool canClaim;
    }

    struct Rate {
        uint256 id;
        uint256 cost;
        address owner;
    }

    event CloseAuction(
        uint256 indexed tokenId,
        address indexed toAddress,
        uint256 indexed price,
        uint256 auctionId
    );

    event TokenCreated(uint256 indexed tokenId, address indexed owner);

    event MultipleTokenCreated(uint256[] tokenIds, address indexed owner);

    event CreateAuction(
        uint256 indexed tokenId,
        address indexed owner,
        uint256 indexed minBidPrice,
        uint256 auctionId
    );

    event ResetAuction(
        uint256 indexed tokenId,
        uint256 indexed minBidPrice,
        uint256 auctionId
    );

    event CreateRate(
        uint256 indexed auctionId,
        address indexed owner,
        uint256 indexed price
    );

    event CloseRate(
        uint256 indexed auctionId,
        address indexed owner,
        uint256 indexed rateId
    );

    event ChangeMinBid(uint256 indexed auctionId, uint256 indexed newMinBid);

    //percent of close auction <creator> NFT token
    uint256 public creatorPercent = 89;

    //percent of close auction <system> NFT token
    uint256 public systemPercent = 11;

    //Time interval for each auction
    uint256 public timeInterval = 24 hours;

    //Time extension if a new bid appears near the end
    uint256 public timeExtension = 15 minutes;

    //Percentage by which new bid should be greater than old
    uint256 public rateStep = 10;

    //min bid amount  WEI
    uint256 public minBid = 0.015 ether;

    //Is pre minting or post minting
    bool public isPreMinting;

    //system address
    address payable public systemAddress = payable(address(0x123));

    // Auction of tokenId
    mapping(uint256 => Auction) public auctionOfToken;

    // rate of auctionId
    mapping(uint256 => Rate) public rateOfAuctionId;

    // creator of tokenId
    mapping(uint256 => address) public tokenCreator;

    // admin addresses
    mapping(address => bool) public adminPool;

    uint256 public auctionCount = 1;
    uint256 public rateCount = 1;
    uint256 private tokensCounter = 0;

    modifier onlyAdmin() {
        require(adminPool[_msgSender()], "Caller is not the admin");
        _;
    }

    // Fee
    function setCreatorFeePercent(uint256 percent) external onlyOwner {
        creatorPercent = percent;
    }

    function setSystemFeePercent(uint256 percent) external onlyOwner {
        systemPercent = percent;
    }

    function setMinBidAmount(uint256 _minBid) external onlyOwner {
        minBid = _minBid;
    }

    function setRateStep(uint256 _newValue) external onlyOwner {
        require(_newValue <= 100, "Rate step too high");
        rateStep = _newValue;
    }

    function setTimeExtension(uint256 _newValue) external onlyOwner {
        require(_newValue <= 24 hours, "Too much extension");
        timeExtension = _newValue;
    }

    function approveAuction(
        uint256 tokenId,
        uint256 serverBidPrice,
        string memory creatorName,
        address creatorAdd,
        address tokenAddress
    ) external onlyAdmin {
        Auction storage auction = auctionOfToken[tokenId];
        Rate memory maxRate = rateOfAuctionId[auction.id];

        require(auction.id != 0, "Auction does not exist");
        require(
            auction.endTime <= block.timestamp,
            "Auction haven't ended yet"
        );

        if (maxRate.cost >= serverBidPrice) {
            auction.canClaim = true;
        } else {
            returnRateToUser(tokenId);
            _setAuctionToMap(tokenId, serverBidPrice, tokenAddress);
            auctionOfToken[tokenId].creatorAddress = creatorAdd;
            auctionOfToken[tokenId].creatorName = creatorName;
            delete rateOfAuctionId[auction.id];
            emit ResetAuction(tokenId, serverBidPrice, auction.id);
        }
    }

    function setSystemAddress(address payable _address) external onlyOwner {
        systemAddress = _address;
    }

    function setTimeInterval(uint256 newTime) external onlyOwner {
        timeInterval = newTime;
    }

    function setAdminPool(address _address, bool value) external onlyOwner {
        adminPool[_address] = value;
    }

    function setMintType(bool value) public onlyOwner {
        isPreMinting = value;
    }

    // Create auctions
    function createTokenAndAuction(
        uint256 minBidPrice,
        string memory _creatorName,
        address tokenAddress
    ) public {
        uint256 tokenId = createToken();
        createAuction(
            tokenId,
            minBidPrice,
            msg.sender,
            _creatorName,
            tokenAddress
        );
    }

    // Create auction
    function createAuction(
        uint256 tokenId,
        uint256 minBidPrice,
        address creatorAddress,
        string memory creatorName,
        address tokenAddress
    ) public payable {
        require(auctionOfToken[tokenId].id == 0, "Auction already exist");

        require(minBidPrice >= minBid, "Min amount error");

        _setAuctionToMap(tokenId, minBidPrice, tokenAddress);

        if (_owners[tokenId] == address(0)) {
            require(!isPreMinting, "Pre minting is active");

            if (creatorAddress == address(0)) {
                auctionOfToken[tokenId].creatorAddress = systemAddress;
            } else {
                auctionOfToken[tokenId].creatorAddress = creatorAddress;
            }

            bool isEthTransaction = tokenAddress == address(0);

            if (isEthTransaction)
                require(msg.value >= minBid, "Not enough Eth for minBid");

            if (!isEthTransaction) {
                require(
                    IERC20(tokenAddress).transferFrom(
                        _msgSender(),
                        address(this),
                        minBid
                    ),
                    "Payment token transfer error."
                );
            }

            _setRateToAuction(
                auctionOfToken[tokenId].id,
                _msgSender(),
                minBid,
                tokenId
            );
        } else {
            require(
                _msgSender() == _owners[tokenId],
                "Auction creator not caller"
            );
            auctionOfToken[tokenId].creatorAddress = _owners[tokenId];
        }

        auctionOfToken[tokenId].creatorName = creatorName;

        emit CreateAuction(
            tokenId,
            _msgSender(),
            minBidPrice,
            auctionOfToken[tokenId].id
        );
    }

    // Close auction by user
    function closeAuctionByUser(uint256 tokenId) public {
        Auction memory auction = auctionOfToken[tokenId];
        require(auction.id != 0, "Auction not exist");

        require(
            ERC721.ownerOf(tokenId) == _msgSender() ||
                _msgSender() == auction.auctionCreator,
            "ERC721: transfer of token that is not own"
        );

        returnRateToUser(tokenId);

        delete auctionOfToken[tokenId];
        delete rateOfAuctionId[auction.id];

        emit CloseAuction(tokenId, address(0), 0, auction.id);
    }

    // Close auction by admin
    function closeAuctionByAdmin(uint256 tokenId) public onlyAdmin {
        Auction memory auction = auctionOfToken[tokenId];
        require(auction.id != 0, "Auction not exist");

        returnRateToUser(tokenId);

        delete auctionOfToken[tokenId];
        delete rateOfAuctionId[auction.id];

        emit CloseAuction(auction.tokenId, address(0), 0, auction.id);
    }

    function returnRateToUser(uint256 tokenId) private {
        Auction memory auction = auctionOfToken[tokenId];
        Rate memory oldRate = rateOfAuctionId[auction.id];

        if (oldRate.id != 0) {
            address payable owner = payable(oldRate.owner);

            if (auction.tokenAddress == address(0)) {
                owner.transfer(oldRate.cost);
            } else {
                require(
                    IERC20(auction.tokenAddress).transfer(owner, oldRate.cost),
                    "Payment token transfer error."
                );
            }
        }
    }

    function createRate(uint256 tokenId, uint256 tokensAmount) public payable {
        require(auctionOfToken[tokenId].id != 0, "Auction not exist");

        Auction memory auction = auctionOfToken[tokenId];
        Rate memory maxRate = rateOfAuctionId[auction.id];

        bool isEthTransaction = auction.tokenAddress == address(0);

        if (isEthTransaction) tokensAmount = msg.value;

        if (block.timestamp > auction.endTime.sub(timeExtension)) {
            auctionOfToken[tokenId].endTime += timeExtension;
        }

        require(
            tokensAmount >
                (
                    maxRate.cost > auction.minBidPrice
                        ? maxRate.cost
                        : auction.minBidPrice
                ).mul(rateStep + 100).div(100),
            "Cost should be greater than previous bid + {rateStep}%"
        );

        if (!isEthTransaction) {
            require(
                IERC20(auction.tokenAddress).transferFrom(
                    _msgSender(),
                    address(this),
                    tokensAmount
                ),
                "Payment token transfer error."
            );
        }

        auctionOfToken[tokenId].minBidPrice = tokensAmount;

        _setRateToAuction(auction.id, _msgSender(), tokensAmount, tokenId);

        emit CreateRate(auction.id, _msgSender(), tokensAmount);
    }

    function closePendingAuction(uint256 tokenId) public {
        Auction memory auction = auctionOfToken[tokenId];

        require(auction.endTime <= block.timestamp, "This is active auction");

        Rate memory maxRate = rateOfAuctionId[auction.id];

        address payable _creatorAddress = payable(auction.creatorAddress);

        if (maxRate.owner != address(0)) {
            if (_owners[tokenId] == address(0)) {
                require(auction.canClaim, "Not approved from server yet");
                _safeMint(maxRate.owner, tokenId);
            } else {
                // Transfer token
                _safeTransfer(
                    _creatorAddress,
                    maxRate.owner,
                    auction.tokenId,
                    ""
                );
            }

            if (auction.tokenAddress == address(0)) {
                //Send money to creator
                _creatorAddress.transfer(
                    getQuantityByTotalAndPercent(maxRate.cost, creatorPercent)
                );
                //Send money to system
                systemAddress.transfer(
                    getQuantityByTotalAndPercent(maxRate.cost, systemPercent)
                );
            } else {
                //Send money to system
                require(
                    IERC20(auction.tokenAddress).transfer(
                        systemAddress,
                        getQuantityByTotalAndPercent(
                            maxRate.cost,
                            systemPercent
                        )
                    ),
                    "Payment token transfer error."
                );
                //Send money to creator
                require(
                    IERC20(auction.tokenAddress).transfer(
                        _creatorAddress,
                        getQuantityByTotalAndPercent(
                            maxRate.cost,
                            creatorPercent
                        )
                    ),
                    "Payment token transfer error."
                );
            }
        }
        delete auctionOfToken[tokenId];
        delete rateOfAuctionId[auction.id];

        emit CloseAuction(tokenId, maxRate.owner, maxRate.cost, auction.id);
    }

    function _setRateToAuction(
        uint256 auctionId,
        address rateOwnAddress,
        uint256 cost,
        uint256 tokenId
    ) private {
        Rate memory oldRate = rateOfAuctionId[auctionId];
        Auction memory auction = auctionOfToken[tokenId];

        if (oldRate.id != 0) {
            address payable owner = payable(oldRate.owner);

            if (auction.tokenAddress == address(0)) {
                owner.transfer(oldRate.cost);
            } else {
                require(
                    IERC20(auction.tokenAddress).transfer(owner, oldRate.cost),
                    "Payment token transfer error."
                );
            }
        }

        Rate memory rate;
        rate.cost = cost;
        rate.owner = rateOwnAddress;
        rate.id = rateCount;

        rateCount = rateCount + 1;
        rateOfAuctionId[auctionId] = rate;
    }

    function getMinBidFromAuction(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        require(auctionOfToken[tokenId].id != 0, "Auction not exist");
        Auction memory auction = auctionOfToken[tokenId];

        uint256 minAmount = auction.minBidPrice;

        return minAmount;
    }

    function _setAuctionToMap(
        uint256 _tokenId,
        uint256 _minBidPrice,
        address tokenAddress
    ) private {
        Auction memory auction;

        auction.tokenId = _tokenId;
        auction.id = auctionCount;
        auction.startTime = block.timestamp;
        auction.endTime = block.timestamp + timeInterval;
        auction.minBidPrice = _minBidPrice;
        auction.tokenAddress = tokenAddress;
        auction.auctionCreator = _msgSender();

        auctionOfToken[_tokenId] = auction;

        auctionCount++;
    }

    // Create tokens
    function createToken() public returns (uint256) {
        require(isPreMinting, "Post minting is active");

        uint256 tokenId = totalSupply();
        while (ownerOf(tokenId) != address(0)) {
            tokenId++;
        }
        _safeMint(_msgSender(), tokenId);
        tokensCounter++;

        emit TokenCreated(tokenId, _msgSender());
        return tokenId;
    }

    function createMultipleTokens(uint256 count)
        public
        returns (uint256[] memory)
    {
        require(count <= 50, "Max limit 50 tokens");
        require(isPreMinting, "Post minting is active");

        uint256[] memory tokensArray = new uint256[](count);

        for (uint256 i = 0; i < count; i++) {
            uint256 tokenId = totalSupply();
            while (ownerOf(tokenId) != address(0)) {
                tokenId++;
            }
            _safeMint(_msgSender(), tokenId);
            tokensCounter++;
            tokensArray[i] = tokenId;
        }
        emit MultipleTokenCreated(tokensArray, _msgSender());
        return tokensArray;
    }

    function getQuantityByTotalAndPercent(uint256 totalCount, uint256 percent)
        public
        pure
        returns (uint256)
    {
        if (percent == 0) return 0;

        return totalCount.mul(percent).div(100);
    }

    function changeTokensOwner(address newAddress) public {
        uint256[] memory tokens = tokensOfOwner(_msgSender());

        for (uint256 i = 0; i < tokens.length; i++) {
            _safeTransfer(_msgSender(), newAddress, tokens[i], "");
            tokenCreator[tokens[i]] = newAddress;
        }
    }

    function withDraw(address _address) public onlyOwner {
        address payable owner = payable(address(uint160(_msgSender())));

        if (_address == address(0)) {
            owner.transfer(address(this).balance);
        } else {
            require(
                IERC20(_address).transfer(
                    _msgSender(),
                    IERC20(_address).balanceOf(address(this))
                ),
                "Payment token transfer error."
            );
        }
    }

    // Token name
    string private _name = "NFT";

    // Token symbol
    string private _symbol = "NFT";

    // Mapping from token ID to owner address
    mapping(uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping(address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping(uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC165, IERC165)
        returns (bool)
    {
        return
            interfaceId == type(IERC721).interfaceId ||
            interfaceId == type(IERC721Metadata).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner)
        public
        view
        virtual
        override
        returns (uint256)
    {
        require(
            owner != address(0),
            "ERC721: balance query for the zero address"
        );
        return _balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId)
        public
        view
        virtual
        override
        returns (address)
    {
        address owner = _owners[tokenId];
        require(
            owner != address(0),
            "ERC721: owner query for nonexistent token"
        );
        return owner;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        string memory baseURI = _baseURI();
        return
            bytes(baseURI).length > 0
                ? string(abi.encodePacked(baseURI, tokenId.toString()))
                : "";
    }

    /**
     * @dev Base URI for computing {tokenURI}. Empty by default, can be overriden
     * in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "https://naftyart.com/token/";
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(
            _msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId)
        public
        view
        virtual
        override
        returns (address)
    {
        require(
            _exists(tokenId),
            "ERC721: approved query for nonexistent token"
        );

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved)
        public
        virtual
        override
    {
        require(operator != _msgSender(), "ERC721: approve to caller");

        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator)
        public
        view
        virtual
        override
        returns (bool)
    {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        //solhint-disable-next-line max-line-length

        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) public virtual override {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "ERC721: transfer caller is not owner nor approved"
        );
        _safeTransfer(from, to, tokenId, _data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `_data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _transfer(from, to, tokenId);
        require(
            _checkOnERC721Received(from, to, tokenId, _data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId)
        internal
        view
        virtual
        returns (bool)
    {
        require(
            _exists(tokenId),
            "ERC721: operator query for nonexistent token"
        );
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner ||
            getApproved(tokenId) == spender ||
            isApprovedForAll(owner, spender));
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(
        address to,
        uint256 tokenId,
        bytes memory _data
    ) internal virtual {
        _mint(to, tokenId);
        require(
            _checkOnERC721Received(address(0), to, tokenId, _data),
            "ERC721: transfer to non ERC721Receiver implementer"
        );
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        require(
            ERC721.ownerOf(tokenId) == from,
            "ERC721: transfer of token that is not own"
        );
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits a {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721.ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory _data
    ) private returns (bool) {
        if (to.isContract()) {
            try
                IERC721Receiver(to).onERC721Received(
                    _msgSender(),
                    from,
                    tokenId,
                    _data
                )
            returns (bytes4 retval) {
                return retval == IERC721Receiver(to).onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert(
                        "ERC721: transfer to non ERC721Receiver implementer"
                    );
                } else {
                    // solhint-disable-next-line no-inline-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {
        if (from == address(0)) {
            _addTokenToAllTokensEnumeration(tokenId);
        } else if (from != to) {
            _removeTokenFromOwnerEnumeration(from, tokenId);
        }
        if (to == address(0)) {
            _removeTokenFromAllTokensEnumeration(tokenId);
        } else if (to != from) {
            _addTokenToOwnerEnumeration(to, tokenId);
        }
    }

    // Mapping from owner to list of owned token IDs
    mapping(address => uint256[]) private _ownedTokens;

    // Mapping from token ID to index of the owner tokens list
    mapping(uint256 => uint256) private _ownedTokensIndex;

    // Array with all token ids, used for enumeration
    uint256[] private _allTokens;

    // Mapping from token id to position in the allTokens array
    mapping(uint256 => uint256) private _allTokensIndex;

    function totalSupply() public view returns (uint256) {
        return _allTokens.length;
    }

    function tokensOfOwner(address owner)
        public
        view
        returns (uint256[] memory)
    {
        return _tokensOfOwner(owner);
    }

    function _tokensOfOwner(address owner)
        internal
        view
        returns (uint256[] storage)
    {
        return _ownedTokens[owner];
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        _ownedTokensIndex[tokenId] = _ownedTokens[to].length;
        _ownedTokens[to].push(tokenId);
    }

    function _addTokenToAllTokensEnumeration(uint256 tokenId) private {
        _allTokensIndex[tokenId] = _allTokens.length;
        _allTokens.push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId)
        private
    {
        // To prevent a gap in from's tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _ownedTokens[from].length.sub(1);
        uint256 tokenIndex = _ownedTokensIndex[tokenId];

        if (tokenIndex != lastTokenIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastTokenIndex];

            _ownedTokens[from][tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
            _ownedTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index
        }
        _ownedTokens[from].pop();
    }

    function _removeTokenFromAllTokensEnumeration(uint256 tokenId) private {
        // To prevent a gap in the tokens array, we store the last token in the index of the token to delete, and
        // then delete the last slot (swap and pop).

        uint256 lastTokenIndex = _allTokens.length.sub(1);
        uint256 tokenIndex = _allTokensIndex[tokenId];

        // When the token to delete is the last token, the swap operation is unnecessary. However, since this occurs so
        // rarely (when the last minted token is burnt) that we still do the swap here to avoid the gas cost of adding
        // an 'if' statement (like in _removeTokenFromOwnerEnumeration)
        uint256 lastTokenId = _allTokens[lastTokenIndex];

        _allTokens[tokenIndex] = lastTokenId; // Move the last token to the slot of the to-delete token
        _allTokensIndex[lastTokenId] = tokenIndex; // Update the moved token's index

        // This also deletes the contents at the last position of the array
        _allTokens.pop();
        _allTokensIndex[tokenId] = 0;
    }
}
