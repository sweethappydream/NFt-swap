pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract NFTSwap is ReentrancyGuard, Ownable {
    address payable public swapOwner;

    using Counters for Counters.Counter;
    Counters.Counter private _itemCounter;
    Counters.Counter private _itemSoldCounter;

    uint256 public swapFee = 10000000000000000; // 0.01 ETH

    struct ERC20Details {
        address[] tokenAddrs;
        uint256[] amounts;
    }

    struct ERC721Details {
        address tokenAddr;
        uint256[] ids;
    }

    enum State {
        Created,
        Release,
        Cancel
    }

    struct SwapItem {
        uint256 id;
        ERC721Details[] erc721Tokens;
        ERC20Details erc20Tokens;
        address payable seller;
        address payable buyer;
        uint256 offerCount;
        State state;
    }

    struct SwapOffer {
        uint256 id;
        uint256 swapItemId;
        ERC721Details[] erc721Tokens;
        ERC20Details erc20Tokens;
        address payable buyer;
        uint256 offerEndTime;
        uint256 creationTime;
    }

    mapping(uint256 => SwapItem) private swapItems;
    mapping(uint256 => mapping(uint256 => SwapOffer)) private swapOffers;

    bool openSwap = false;

    event SwapItemCreated(
        uint256 swapItemID,
        ERC721Details[] erc721Tokens,
        ERC20Details erc20Tokens,
        address seller,
        address buyer,
        State state
    );

    event SwapItemSold(
        uint256 swapItemID,
        ERC721Details[] erc721Tokens,
        ERC20Details erc20Tokens,
        address seller,
        address buyer,
        State state
    );

    //this is newly inserted event. 
    event SwapItemCancelld(
        uint256 swapItemID,
        ERC721Details[] erc721Tokens,
        ERC20Details erc20Tokens,
        address seller,
        address buyer,
        State state
    );

    event SwapOfferCreated(
        uint256 swapItemID,
        ERC721Details[] erc721Tokens,
        ERC20Details erc20Tokens,
        address buyer,
        uint256 creationTime
    );

    constructor() {
        swapOwner = payable(msg.sender);
    }

    /**
     * Manage the Swap
     */
    function setOpenOffer(bool _new) external onlyOwner {
        openSwap = _new;
    }

    /**
     * Set the Swap Owner Address
     */
    function setSwapOwner(address swapper) external onlyOwner {
        swapOwner = payable(swapper);
    }

    /**
     * Checking the assets
     */
    function _checkAssets(
        ERC721Details[] memory erc721Details,
        ERC20Details memory erc20Details,
        address offer
    ) internal view {
        for (uint256 i = 0; i < erc721Details.length; i++) {
            require(
                erc721Details[i].ids.length > 0,
                "Non included ERC721 token"
            );

            for (uint256 j = 0; j < erc721Details[i].ids.length; j++) {
                require(
                    IERC721(erc721Details[i].tokenAddr).getApproved(
                        erc721Details[i].ids[j]
                    ) == address(this),
                    "ERC721 tokens must be approved to swap contract"
                );
            }
        }

        // check duplicated token address
        for (uint256 i = 0; i < erc20Details.tokenAddrs.length; i++) {
            uint256 tokenCount = 0;
            for (uint256 j = 0; j < erc20Details.tokenAddrs.length; j++) {
                if (erc20Details.tokenAddrs[i] == erc20Details.tokenAddrs[j]) {
                    tokenCount++;
                }
            }

            require(tokenCount == 1, "Invalid ERC20 tokens");
        }

        for (uint256 i = 0; i < erc20Details.tokenAddrs.length; i++) {
            require(
                IERC20(erc20Details.tokenAddrs[i]).allowance(
                    offer,
                    address(this)
                ) >= erc20Details.amounts[i],
                "ERC20 tokens must be approved to swap contract"
            );
        }
    }

    /**
     * Transfer assets to Swap Contract
     */
    function _transferAssetsHelper(
        ERC721Details[] memory erc721Details,
        ERC20Details memory erc20Details,
        address from,
        address to
    ) internal {
        for (uint256 i = 0; i < erc721Details.length; i++) {
            for (uint256 j = 0; j < erc721Details[i].ids.length; j++) {
                IERC721(erc721Details[i].tokenAddr).transferFrom(
                    from,
                    to,
                    erc721Details[i].ids[j]
                );
            }
        }

        for (uint256 i = 0; i < erc20Details.tokenAddrs.length; i++) {
            IERC20(erc20Details.tokenAddrs[i]).transferFrom(
                from,
                to,
                erc20Details.amounts[i]
            );
        }
    }

    /**
     * Return assets to holders
     * ERC20 requires approve from contract to holder
     */
    function _returnAssetsHelper(
        ERC721Details[] memory erc721Details,
        ERC20Details memory erc20Details,
        address from,
        address to
    ) internal {
        for (uint256 i = 0; i < erc721Details.length; i++) {
            for (uint256 j = 0; j < erc721Details[i].ids.length; j++) {
                IERC721(erc721Details[i].tokenAddr).transferFrom(
                    from,
                    to,
                    erc721Details[i].ids[j]
                );
            }
        }

        for (uint256 i = 0; i < erc20Details.tokenAddrs.length; i++) {
            IERC20(erc20Details.tokenAddrs[i]).transfer(
                to,
                erc20Details.amounts[i]
            );
        }
    }

    /**
     * create a SwapItem for ERC721 + ERC20 on the Swap List
     * List an NFT
     *
     * Warning User needs to approve assets before list
     */
    function createSwapItem(
        ERC721Details[] memory erc721Details,
        ERC20Details memory erc20Details
    ) public payable nonReentrant {
        require(openSwap, "Swap is not opended");
        require(msg.value == swapFee, "Fee must be equal to listing fee");
        require(erc721Details.length > 0, "SwapItems must include ERC721");

        _checkAssets(erc721Details, erc20Details, msg.sender);

        _transferAssetsHelper(
            erc721Details,
            erc20Details,
            msg.sender,
            address(this)
        );

        _itemCounter.increment();

        uint256 id = _itemCounter.current();
        SwapItem storage newItem = swapItems[id];
        newItem.id = id;
        newItem.erc20Tokens = erc20Details;
        newItem.seller = payable(msg.sender);
        newItem.buyer = payable(address(0));
        newItem.offerCount = 0;
        newItem.state = State.Created;
        for (uint256 i = 0; i < erc721Details.length; i++) {
            newItem.erc721Tokens.push(erc721Details[i]);
        }

        emit SwapItemCreated(
            id,
            erc721Details,
            erc20Details,
            msg.sender,
            address(0),
            State.Created
        );
    }

    /**
     * create the SwapOfferItem
     */
    function createSwapOffer(
        uint256 itemNumber,
        ERC721Details[] memory erc721Details,
        ERC20Details memory erc20Details,
        uint256 timeInterval
    ) public nonReentrant {
        require(erc721Details.length > 0, "SwapItems must include ERC721");
        require(
            swapItems[itemNumber].state == State.Created,
            "This Swap is finished"
        );

        _checkAssets(erc721Details, erc20Details, msg.sender);

        _transferAssetsHelper(
            erc721Details,
            erc20Details,
            msg.sender,
            address(this)
        );

        SwapOffer storage offer = swapOffers[itemNumber][
            swapItems[itemNumber].offerCount
        ];
        offer.id = swapItems[itemNumber].offerCount;
        offer.swapItemId = itemNumber;
        offer.erc20Tokens = erc20Details;
        offer.buyer = payable(msg.sender);
        offer.offerEndTime = block.timestamp + timeInterval;
        offer.creationTime = block.timestamp;
        for (uint256 i = 0; i < erc721Details.length; i++) {
            offer.erc721Tokens.push(erc721Details[i]);
        }

        swapItems[itemNumber].offerCount++;

        emit SwapOfferCreated(
            itemNumber,
            erc721Details,
            erc20Details,
            msg.sender,
            block.timestamp
        );
    }

    /**
     * Confirm & Release the offer
     * Release Swap
     */
    function ConfirmSwap(uint256 itemNumber, uint256 offerNumber)
        public
        nonReentrant
    {
        require(itemNumber <= _itemCounter.current(), "Non exist SwapItem");
        require(
            swapItems[itemNumber].seller == payable(msg.sender),
            "Allowed to only Owner of Assets"
        );
        require(
            swapItems[itemNumber].state == State.Created,
            "SwapItem is released or canceled"
        );
        require(
            swapOffers[itemNumber][offerNumber].offerEndTime > block.timestamp,
            "Offer time is up"
        );

        _returnAssetsHelper(
            swapItems[itemNumber].erc721Tokens,
            swapItems[itemNumber].erc20Tokens,
            address(this),
            swapOffers[itemNumber][offerNumber].buyer
        );

        _returnAssetsHelper(
            swapOffers[itemNumber][offerNumber].erc721Tokens,
            swapOffers[itemNumber][offerNumber].erc20Tokens,
            address(this),
            msg.sender
        );

        swapItems[itemNumber].buyer = swapOffers[itemNumber][offerNumber].buyer;
        swapItems[itemNumber].state = State.Release;

        _itemSoldCounter.increment();

        delete swapOffers[itemNumber][offerNumber];

        swapOwner.transfer(swapFee);

        emit SwapItemSold(
            itemNumber,
            swapItems[itemNumber].erc721Tokens,
            swapItems[itemNumber].erc20Tokens,
            swapItems[itemNumber].seller,
            swapItems[itemNumber].buyer,
            State.Release
        );
    }

    /**
     * Cancel the SwapItem
     */
    function CancelSwapItem(uint256 itemNumber) public nonReentrant {
        require(itemNumber <= _itemCounter.current(), "Non exist SwapItem");

        if (msg.sender != owner())
            require(
                swapItems[itemNumber].seller == payable(msg.sender),
                "Allowed to only Owner of Assets"
            );

        _returnAssetsHelper(
            swapItems[itemNumber].erc721Tokens,
            swapItems[itemNumber].erc20Tokens,
            address(this),
            msg.sender
        );

        swapItems[itemNumber].state = State.Cancel;

        payable(msg.sender).transfer(swapFee);

        //in this situation the item is cancelled, not sold
        //when you see it later you can not understand easily
        //This is corrected from SwapItemSold to SwapItemCancelled 
        emit SwapItemCancelled(
            itemNumber,
            swapItems[itemNumber].erc721Tokens,
            swapItems[itemNumber].erc20Tokens,
            swapItems[itemNumber].seller,
            swapItems[itemNumber].buyer,
            State.Cancel
        );
    }

    /**
     * Release & cancel the offer
     */
    function CancelOffer(uint256 itemNumber, uint256 offerNumber)
        public
        nonReentrant
    {
        require(itemNumber <= _itemCounter.current(), "Non exist SwapItem");
        require(
            swapOffers[itemNumber][offerNumber].buyer == payable(msg.sender),
            "This offer is not your offer"
        );

        _returnAssetsHelper(
            swapOffers[itemNumber][offerNumber].erc721Tokens,
            swapOffers[itemNumber][offerNumber].erc20Tokens,
            address(this),
            msg.sender
        );

        delete swapOffers[itemNumber][offerNumber];
    }

    enum FetchOperator {
        AllSwapItems,
        MySwapItems
    }

    /**
     * Fetch Condition
     */
    function SwapItemCondition(
        SwapItem memory item,
        FetchOperator _op,
        address seller
    ) private pure returns (bool) {
        if (_op == FetchOperator.AllSwapItems) {
            return (item.state == State.Created) ? true : false;
        } else {
            return (item.seller == payable(seller)) ? true : false;
        }
    }

    /**
     * Fetch helper
     */
    function fetchHelper(address seller, FetchOperator _op)
        private
        view
        returns (SwapItem[] memory)
    {
        uint256 total = _itemCounter.current();
        uint256 itemCount = 0;
        for (uint256 i = 1; i <= total; i++) {
            if (SwapItemCondition(swapItems[i], _op, seller)) {
                itemCount++;
            }
        }

        uint256 index = 0;
        SwapItem[] memory items = new SwapItem[](itemCount);
        for (uint256 i = 1; i <= total; i++) {
            if (SwapItemCondition(swapItems[i], _op, seller)) {
                items[index] = swapItems[i];
                index++;
            }
        }

        return items;
    }

    /**
     * Fetch all created SwapItems
     */
    function GetSwapItems() public view returns (SwapItem[] memory) {
        return fetchHelper(address(this), FetchOperator.AllSwapItems);
    }

    /**
     * Fetch My SwapItems
     */
    function GetOwnedSwapItems(address seller)
        public
        view
        returns (SwapItem[] memory)
    {
        return fetchHelper(seller, FetchOperator.MySwapItems);
    }

    /**
     * Get SwapItem by Index
     */
    function GetSwapItembyIndex(uint256 itemNumber)
        public
        view
        returns (SwapItem memory)
    {
        return swapItems[itemNumber];
    }

    /**
     * Get SwapOffers by Index
     */
    function GetSwapOffersByIndex(uint256 itemNumber)
        public
        view
        returns (SwapOffer[] memory)
    {
        uint256 total = _itemCounter.current();
        uint256 itemCount = 0;
        for (uint256 i = 1; i <= total; i++) {
            for (uint256 j = 0; j < swapItems[i].offerCount; j++) {
                if (swapOffers[i][j].swapItemId == itemNumber) {
                    itemCount++;
                }
            }
        }

        uint256 index = 0;
        SwapOffer[] memory items = new SwapOffer[](itemCount);
        for (uint256 i = 1; i <= total; i++) {
            for (uint256 j = 0; j < swapItems[i].offerCount; j++) {
                if (swapOffers[i][j].swapItemId == itemNumber) {
                    items[index] = swapOffers[i][j];
                    index++;
                }
            }
        }

        return items;
    }

    /**
     * Fetch My SwapOffers
     */
    function GetSwapOffers(address offer)
        public
        view
        returns (SwapOffer[] memory)
    {
        uint256 total = _itemCounter.current();
        uint256 itemCount = 0;
        for (uint256 i = 1; i <= total; i++) {
            for (uint256 j = 0; j < swapItems[i].offerCount; j++) {
                if (swapOffers[i][j].buyer == offer) {
                    itemCount++;
                }
            }
        }

        uint256 index = 0;
        SwapOffer[] memory items = new SwapOffer[](itemCount);
        for (uint256 i = 1; i <= total; i++) {
            for (uint256 j = 0; j < swapItems[i].offerCount; j++) {
                if (swapOffers[i][j].buyer == offer) {
                    items[index] = swapOffers[i][j];
                    index++;
                }
            }
        }

        return items;
    }
}
