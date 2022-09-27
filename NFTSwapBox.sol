// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./interface/IERC20.sol";
import "./interface/IERC721.sol";
import "./interface/IERC1155.sol";

contract NFTSwapBox is ReentrancyGuard, Ownable {
    address payable public swapOwner;
    uint256 private _itemCounter;
    uint256[] public swapFees = [
        0.01 ether,
        0.02 ether,
        0.01 ether,
        0.01 ether
    ];
    bool openSwap = false;

    struct ERC20Details {
        address[] tokenAddrs;
        uint256[] amounts;
    }
    struct ERC721Details {
        address tokenAddr;
        uint256[] ids;
    }
    struct ERC1155Details {
        address tokenAddr;
        uint256[] ids;
        uint256[] amounts;
    }

    enum State {
        Initiated,
        Waiting_for_offers,
        Offered,
        Destroyed
    }

    struct BoxOffer {
        uint256 boxID;
        bool active;
    }
    struct SwapBox {
        uint256 id;
        address owner;
        ERC721Details[] erc721Tokens;
        ERC20Details erc20Tokens;
        ERC1155Details[] erc1155Tokens;
        uint256 gasTokenAmount;
        uint256 createdTime;
        State state;
        // this shows the offered ID lists If this box state is waiting
        // this shows the waiting ID lists If this box state is offer
        BoxOffer[] offers;
    }

    struct SwapBoxConfig {
        bool usingERC721WhiteList;
        bool usingERC1155WhiteList;
        uint256 NFTTokenCount;
        uint256 ERC20TokenCount;
    }

    SwapBoxConfig private swapConfig;

    //I replaced the array for whitelist to mapping
    //when the number of tokens in whitelist increases, it is really gas consuming to use for loop every time
    //by using mapping you can easily find if the specified token is in the whitelist
    // I didn't correct the all code below related to whitelist
    mapping(address => bool) isERC20Exist;
    mapping(address => bool) isERC721Exist;
    mapping(address => bool) isERC1155Exist;
    // address[] public whitelistERC20Tokens;
    // address[] public whitelistERC721Tokens;
    // address[] public whitelistERC1155Tokens;

    mapping(uint256 => SwapBox) private swapBoxes;

    event SwapBoxState(
        uint256 swapItemID,
        address owner,
        State state,
        uint256 createdTime,
        uint256 updateTime,
        uint256 gasTokenAmount,
        ERC721Details[] erc721Tokens,
        ERC20Details erc20Tokens,
        ERC1155Details[] erc1155Tokens
    );

    event Swaped(
        uint256 listID,
        address listOwner,
        uint256 offerID,
        address offerOwner
    );

    constructor() {
        swapOwner = payable(msg.sender);

        swapConfig.usingERC721WhiteList = true;
        swapConfig.usingERC1155WhiteList = true;
        swapConfig.NFTTokenCount = 5;
        swapConfig.ERC20TokenCount = 5;
    }

    modifier isOpenForSwap() {
        require(openSwap, "Swap is not allowed");
        _;
    }

    // Set the Swap state
    function setSwapState(bool _new) external onlyOwner {
        openSwap = _new;
    }

    // Set the Swap Owner Address
    function setSwapOwner(address swapper) external onlyOwner {
        swapOwner = payable(swapper);
    }

    // Set SwapContract Fees
    function setCreateFee(uint256 value) external onlyOwner {
        swapFees[0] = value;
    }

    function setWaitingOfferFee(uint256 value) external onlyOwner {
        swapFees[1] = value;
    }

    function setOfferFee(uint256 value) external onlyOwner {
        swapFees[2] = value;
    }

    function setDestroyFee(uint256 value) external onlyOwner {
        swapFees[3] = value;
    }

    // Get SwapContract Fees
    function getSwapPrices() public view returns (uint256[] memory) {
        return swapFees;
    }

    function addWhiteListToken(address erc20Token) external onlyOwner {
        require(
            validateWhiteListERC20Token(erc20Token) == false,
            "Exist Token"
        );
        whitelistERC20Tokens.push(erc20Token);
    }

    function setUsingERC721Whitelist(bool usingList) external onlyOwner {
        swapConfig.usingERC721WhiteList = usingList;
    }

    function setUsingERC1155Whitelist(bool usingList) external onlyOwner {
        swapConfig.usingERC1155WhiteList = usingList;
    }

    function getERC20WhiteListTokens() public view returns (address[] memory) {
        return whitelistERC20Tokens;
    }

    function removeFromERC20WhiteList(uint256 index) external onlyOwner {
        require(index < whitelistERC20Tokens.length, "Invalid element");
        whitelistERC20Tokens[index] = whitelistERC20Tokens[
            whitelistERC20Tokens.length - 1
        ];
        whitelistERC20Tokens.pop();
    }

    function addWhiliteListERC721Token(address erc721Token) external onlyOwner {
        require(
            validateWhiteListERC721Token(erc721Token) == false,
            "Exist Token"
        );
        whitelistERC721Tokens.push(erc721Token);
    }

    function getERC721WhiteListTokens() public view returns (address[] memory) {
        return whitelistERC721Tokens;
    }

    function removeFromERC721WhiteList(uint256 index) external onlyOwner {
        require(index < whitelistERC721Tokens.length, "Invalid element");
        whitelistERC721Tokens[index] = whitelistERC721Tokens[
            whitelistERC721Tokens.length - 1
        ];
        whitelistERC721Tokens.pop();
    }

    function addWhiliteListERC1155Token(address erc1155Token)
        external
        onlyOwner
    {
        require(
            validateWhiteListERC1155Token(erc1155Token) == false,
            "Exist Token"
        );
        whitelistERC1155Tokens.push(erc1155Token);
    }

    function getERC1155WhiteListTokens()
        public
        view
        returns (address[] memory)
    {
        return whitelistERC1155Tokens;
    }

    function removeFromERC1155WhiteList(uint256 index) external onlyOwner {
        require(index < whitelistERC1155Tokens.length, "Invalid element");
        whitelistERC1155Tokens[index] = whitelistERC1155Tokens[
            whitelistERC1155Tokens.length - 1
        ];
        whitelistERC1155Tokens.pop();
    }

    // Checking whitelist ERC20 Token
    function validateWhiteListERC20Token(address erc20Token)
        public
        view
        returns (bool)
    {
        for (uint256 i = 0; i < whitelistERC20Tokens.length; i++) {
            if (whitelistERC20Tokens[i] == erc20Token) {
                return true;
            }
        }

        return false;
    }

    // Checking whitelist ERC721 Token
    function validateWhiteListERC721Token(address erc721Token)
        public
        view
        returns (bool)
    {
        if (!swapConfig.usingERC721WhiteList) return true;

        for (uint256 i = 0; i < whitelistERC721Tokens.length; i++) {
            if (whitelistERC721Tokens[i] == erc721Token) {
                return true;
            }
        }

        return false;
    }

    function validateWhiteListERC1155Token(address erc1155Token)
        public
        view
        returns (bool)
    {
        if (!swapConfig.usingERC1155WhiteList) return true;

        for (uint256 i = 0; i < whitelistERC721Tokens.length; i++) {
            if (whitelistERC1155Tokens[i] == erc1155Token) {
                return true;
            }
        }

        return false;
    }

    // Destroy All SwapBox. Emergency Function
    function destroyAllSwapBox() external onlyOwner {
        for (uint256 i = 1; i <= _itemCounter; i++) {
            if (swapBoxes[i].state != State.Destroyed) {
                swapBoxes[i].state = State.Destroyed;

                _returnAssetsHelper(
                    swapBoxes[i].erc721Tokens,
                    swapBoxes[i].erc20Tokens,
                    swapBoxes[i].erc1155Tokens,
                    swapBoxes[i].gasTokenAmount,
                    address(this),
                    swapBoxes[i].owner
                );
            }
        }
    }

    // function withDraw() external onlyOwner {
    //     uint balance = address(this).balance;
    //     swapOwner.transfer(balance);
    // }

    // Checking the assets
    function _checkAssets(
        ERC721Details[] memory erc721Details,
        ERC20Details memory erc20Details,
        ERC1155Details[] memory erc1155Details,
        address offer
    ) internal view {
        require(
            (erc721Details.length + erc1155Details.length) <=
                swapConfig.NFTTokenCount,
            "Too much NFTs selected"
        );

        for (uint256 i = 0; i < erc721Details.length; i++) {
            require(
                validateWhiteListERC721Token(erc721Details[i].tokenAddr),
                "Not Allowed ERC721 Token"
            );
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
        require(
            erc20Details.tokenAddrs.length <= swapConfig.ERC20TokenCount,
            "Too much ERC20 tokens selected"
        );
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
                validateWhiteListERC20Token(erc20Details.tokenAddrs[i]),
                "Not Allowed ERC20 Tokens"
            );
            require(
                IERC20(erc20Details.tokenAddrs[i]).allowance(
                    offer,
                    address(this)
                ) >= erc20Details.amounts[i],
                "ERC20 tokens must be approved to swap contract"
            );
            require(
                IERC20(erc20Details.tokenAddrs[i]).balanceOf(offer) >=
                    erc20Details.amounts[i],
                "Insufficient ERC20 tokens"
            );
        }

        for (uint256 i = 0; i < erc1155Details.length; i++) {
            require(
                validateWhiteListERC1155Token(erc1155Details[i].tokenAddr),
                "Not Allowed ERC721 Token"
            );
            for (uint256 j = 0; j < erc1155Details[i].ids.length; i++) {
                require(
                    IERC1155(erc1155Details[i].tokenAddr).balanceOf(
                        offer,
                        erc1155Details[i].ids[j]
                    ) > 0,
                    "This token not exist"
                );
                require(
                    IERC1155(erc1155Details[i].tokenAddr).isApprovedForAll(
                        offer,
                        address(this)
                    ),
                    "ERC1155 token must be approved to swap contract"
                );
            }
        }
    }

    // Transfer assets to Swap Contract
    function _transferAssetsHelper(
        ERC721Details[] memory erc721Details,
        ERC20Details memory erc20Details,
        ERC1155Details[] memory erc1155Details,
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

        for (uint256 i = 0; i < erc1155Details.length; i++) {
            IERC1155(erc1155Details[i].tokenAddr).safeBatchTransferFrom(
                from,
                to,
                erc1155Details[i].ids,
                erc1155Details[i].amounts,
                ""
            );
        }
    }

    // Return assets to holders/. ERC20 requires approve from contract to holder
    function _returnAssetsHelper(
        ERC721Details[] memory erc721Details,
        ERC20Details memory erc20Details,
        ERC1155Details[] memory erc1155Details,
        uint256 gasTokenAmount,
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

        for (uint256 i = 0; i < erc1155Details.length; i++) {
            IERC1155(erc1155Details[i].tokenAddr).safeBatchTransferFrom(
                from,
                to,
                erc1155Details[i].ids,
                erc1155Details[i].amounts,
                ""
            );
        }

        if (gasTokenAmount > 0) {
            payable(to).transfer(gasTokenAmount);
        }
    }

    // Checking the exist boxID. If checkingActive is true, it will check activity
    function _existBoxID(
        SwapBox memory box,
        uint256 boxID,
        bool checkingActive
    ) internal pure returns (bool) {
        for (uint256 i = 0; i < box.offers.length; i++) {
            if (checkingActive) {
                if (
                    checkingActive &&
                    box.offers[i].boxID == boxID &&
                    box.offers[i].active
                ) {
                    return true;
                }
            } else {
                if (box.offers[i].boxID == boxID) {
                    return true;
                }
            }
        }

        return false;
    }

    // Insert & Update the SwapOffer to Swap Box. Set active value of Swap Offer
    function _putSwapOffer(
        uint256 listID,
        uint256 boxID,
        bool active
    ) internal {
        for (uint256 i = 0; i < swapBoxes[listID].offers.length; i++) {
            if (swapBoxes[listID].offers[i].boxID == boxID) {
                swapBoxes[listID].offers[i].active = active;
                return;
            }
        }

        swapBoxes[listID].offers.push(BoxOffer(boxID, active));
    }

    // Create Swap Box. Warning User needs to approve assets before list
    function createBox(
        ERC721Details[] memory erc721Details,
        ERC20Details memory erc20Details,
        ERC1155Details[] memory erc1155Details,
        uint256 gasTokenAmount
    ) public payable isOpenForSwap nonReentrant {
        // require(erc721Details.length > 0, "SwapItems must include ERC721");
        require(
            msg.value >= (swapFees[0] + gasTokenAmount),
            "Insufficient Creating Box Fee"
        );

        _checkAssets(erc721Details, erc20Details, erc1155Details, msg.sender);
        _transferAssetsHelper(
            erc721Details,
            erc20Details,
            erc1155Details,
            msg.sender,
            address(this)
        );

        _itemCounter++;

        SwapBox storage box = swapBoxes[_itemCounter];
        box.id = _itemCounter;
        box.erc20Tokens = erc20Details;
        box.owner = msg.sender;
        box.state = State.Initiated;
        box.createdTime = block.timestamp;
        box.gasTokenAmount = gasTokenAmount;
        for (uint256 i = 0; i < erc721Details.length; i++) {
            box.erc721Tokens.push(erc721Details[i]);
        }
        for (uint256 i = 0; i < erc1155Details.length; i++) {
            box.erc1155Tokens.push(erc1155Details[i]);
        }

        if (gasTokenAmount > 0) swapOwner.transfer(swapFees[0]);

        emit SwapBoxState(
            _itemCounter,
            msg.sender,
            State.Initiated,
            block.timestamp,
            block.timestamp,
            gasTokenAmount,
            erc721Details,
            erc20Details,
            erc1155Details
        );
    }

    // Update the Box to Waiting_for_offers state
    function toWaitingForOffers(uint256 boxID)
        public
        payable
        isOpenForSwap
        nonReentrant
    {
        require(
            swapBoxes[boxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );
        require(
            swapBoxes[boxID].state == State.Initiated,
            "Not Allowed Operation"
        );

        require(msg.value >= swapFees[1], "Insufficient Listing Fee");

        swapBoxes[boxID].state = State.Waiting_for_offers;

        swapOwner.transfer(swapFees[1]);

        emit SwapBoxState(
            boxID,
            msg.sender,
            State.Waiting_for_offers,
            swapBoxes[boxID].createdTime,
            block.timestamp,
            swapBoxes[boxID].gasTokenAmount,
            swapBoxes[boxID].erc721Tokens,
            swapBoxes[boxID].erc20Tokens,
            swapBoxes[boxID].erc1155Tokens
        );
    }

    // update the Box to Offer state
    function toOffer(uint256 boxID) public payable isOpenForSwap nonReentrant {
        require(
            swapBoxes[boxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );
        require(
            swapBoxes[boxID].state == State.Initiated,
            "Not Allowed Operation"
        );

        require(msg.value >= swapFees[2], "Insufficient Offer Fee");

        swapBoxes[boxID].state = State.Offered;

        swapOwner.transfer(swapFees[2]);

        emit SwapBoxState(
            boxID,
            msg.sender,
            State.Offered,
            swapBoxes[boxID].createdTime,
            block.timestamp,
            swapBoxes[boxID].gasTokenAmount,
            swapBoxes[boxID].erc721Tokens,
            swapBoxes[boxID].erc20Tokens,
            swapBoxes[boxID].erc1155Tokens
        );
    }

    // Destroy Box. all assets back to owner's wallet
    function destroyBox(uint256 boxID)
        public
        payable
        isOpenForSwap
        nonReentrant
    {
        require(
            swapBoxes[boxID].state == State.Initiated,
            "Not Allowed Operation"
        );
        require(
            swapBoxes[boxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );

        require(msg.value >= swapFees[3], "Insufficient Offer Fee");

        swapBoxes[boxID].state = State.Destroyed;

        swapOwner.transfer(swapFees[3]);

        _returnAssetsHelper(
            swapBoxes[boxID].erc721Tokens,
            swapBoxes[boxID].erc20Tokens,
            swapBoxes[boxID].erc1155Tokens,
            swapBoxes[boxID].gasTokenAmount,
            address(this),
            msg.sender
        );

        emit SwapBoxState(
            boxID,
            msg.sender,
            State.Destroyed,
            swapBoxes[boxID].createdTime,
            block.timestamp,
            swapBoxes[boxID].gasTokenAmount,
            swapBoxes[boxID].erc721Tokens,
            swapBoxes[boxID].erc20Tokens,
            swapBoxes[boxID].erc1155Tokens
        );
    }

    function withDrawERC20TokenFromBox(uint256 boxID, address erc20Address)
        public
        isOpenForSwap
        nonReentrant
    {
        require(
            swapBoxes[boxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );
        require(
            swapBoxes[boxID].erc20Tokens.tokenAddrs.length > 0,
            "Not exist ERC20 Token on SwapBox"
        );

        for (
            uint256 i = 0;
            i < swapBoxes[boxID].erc20Tokens.tokenAddrs.length;
            i++
        ) {
            if (swapBoxes[boxID].erc20Tokens.tokenAddrs[i] == erc20Address) {
                IERC20(swapBoxes[boxID].erc20Tokens.tokenAddrs[i]).transfer(
                    msg.sender,
                    swapBoxes[boxID].erc20Tokens.amounts[i]
                );

                swapBoxes[boxID].erc20Tokens.tokenAddrs[i] = swapBoxes[boxID]
                    .erc20Tokens
                    .tokenAddrs[
                        swapBoxes[boxID].erc20Tokens.tokenAddrs.length - 1
                    ];
                swapBoxes[boxID].erc20Tokens.amounts[i] = swapBoxes[boxID]
                    .erc20Tokens
                    .amounts[swapBoxes[boxID].erc20Tokens.amounts.length - 1];
                swapBoxes[boxID].erc20Tokens.tokenAddrs.pop();
                swapBoxes[boxID].erc20Tokens.amounts.pop();

                break;
            }
        }

        emit SwapBoxState(
            boxID,
            msg.sender,
            swapBoxes[boxID].state,
            swapBoxes[boxID].createdTime,
            block.timestamp,
            swapBoxes[boxID].gasTokenAmount,
            swapBoxes[boxID].erc721Tokens,
            swapBoxes[boxID].erc20Tokens,
            swapBoxes[boxID].erc1155Tokens
        );
    }

    function withDrawERC721TokenFromBox(
        uint256 boxID,
        address erc721Address,
        uint256 tokenID
    ) public isOpenForSwap nonReentrant {
        require(
            swapBoxes[boxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );
        require(
            swapBoxes[boxID].erc721Tokens.length > 0,
            "Not exist ERC721 Token on SwapBox"
        );

        for (uint256 i = 0; i < swapBoxes[boxID].erc721Tokens.length; i++) {
            if (swapBoxes[boxID].erc721Tokens[i].tokenAddr == erc721Address) {
                for (
                    uint256 j = 0;
                    j < swapBoxes[boxID].erc721Tokens[i].ids.length;
                    j++
                ) {
                    if (swapBoxes[boxID].erc721Tokens[i].ids[j] == tokenID) {
                        IERC721(swapBoxes[boxID].erc721Tokens[i].tokenAddr)
                            .transferFrom(
                                address(this),
                                msg.sender,
                                swapBoxes[boxID].erc721Tokens[i].ids[j]
                            );

                        swapBoxes[boxID].erc721Tokens[i].ids[j] = swapBoxes[
                            boxID
                        ].erc721Tokens[i].ids[
                                swapBoxes[boxID].erc721Tokens[i].ids.length - 1
                            ];
                        swapBoxes[boxID].erc721Tokens[i].ids.pop();

                        break;
                    }
                }

                if (swapBoxes[boxID].erc721Tokens[i].ids.length == 0) {
                    swapBoxes[boxID].erc721Tokens[i] = swapBoxes[boxID]
                        .erc721Tokens[swapBoxes[boxID].erc721Tokens.length - 1];
                    swapBoxes[boxID].erc721Tokens.pop();

                    break;
                }
            }
        }

        emit SwapBoxState(
            boxID,
            msg.sender,
            swapBoxes[boxID].state,
            swapBoxes[boxID].createdTime,
            block.timestamp,
            swapBoxes[boxID].gasTokenAmount,
            swapBoxes[boxID].erc721Tokens,
            swapBoxes[boxID].erc20Tokens,
            swapBoxes[boxID].erc1155Tokens
        );
    }

    function withDrawERC1155TokenFromBox(
        uint256 boxID,
        address erc1155Address,
        uint256 tokenID
    ) public isOpenForSwap nonReentrant {
        require(
            swapBoxes[boxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );
        require(
            swapBoxes[boxID].erc1155Tokens.length > 0,
            "Not exist ERC721 Token on SwapBox"
        );

        for (uint256 i = 0; i < swapBoxes[boxID].erc1155Tokens.length; i++) {
            if (swapBoxes[boxID].erc1155Tokens[i].tokenAddr == erc1155Address) {
                for (
                    uint256 j = 0;
                    j < swapBoxes[boxID].erc1155Tokens[i].ids.length;
                    j++
                ) {
                    if (swapBoxes[boxID].erc1155Tokens[i].ids[j] == tokenID) {
                        IERC1155(swapBoxes[boxID].erc1155Tokens[i].tokenAddr)
                            .safeTransferFrom(
                                address(this),
                                msg.sender,
                                swapBoxes[boxID].erc1155Tokens[i].ids[j],
                                swapBoxes[boxID].erc1155Tokens[i].amounts[j],
                                ""
                            );

                        swapBoxes[boxID].erc1155Tokens[i].ids[j] = swapBoxes[
                            boxID
                        ].erc1155Tokens[i].ids[
                                swapBoxes[boxID].erc1155Tokens[i].ids.length - 1
                            ];
                        swapBoxes[boxID].erc1155Tokens[i].amounts[
                            j
                        ] = swapBoxes[boxID].erc1155Tokens[i].amounts[
                            swapBoxes[boxID].erc1155Tokens[i].amounts.length - 1
                        ];
                        swapBoxes[boxID].erc1155Tokens[i].ids.pop();
                        swapBoxes[boxID].erc1155Tokens[i].amounts.pop();

                        break;
                    }
                }

                if (swapBoxes[boxID].erc1155Tokens[i].ids.length == 0) {
                    swapBoxes[boxID].erc1155Tokens[i] = swapBoxes[boxID]
                        .erc1155Tokens[
                            swapBoxes[boxID].erc1155Tokens.length - 1
                        ];
                    swapBoxes[boxID].erc1155Tokens.pop();

                    break;
                }
            }
        }

        emit SwapBoxState(
            boxID,
            msg.sender,
            swapBoxes[boxID].state,
            swapBoxes[boxID].createdTime,
            block.timestamp,
            swapBoxes[boxID].gasTokenAmount,
            swapBoxes[boxID].erc721Tokens,
            swapBoxes[boxID].erc20Tokens,
            swapBoxes[boxID].erc1155Tokens
        );
    }

    function withDrawGasTokenFromBox(uint256 boxID)
        public
        isOpenForSwap
        nonReentrant
    {
        require(
            swapBoxes[boxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );
        require(
            swapBoxes[boxID].gasTokenAmount > 0,
            "Not exist Gas Token on SwapBox"
        );

        payable(msg.sender).transfer(swapBoxes[boxID].gasTokenAmount);

        swapBoxes[boxID].gasTokenAmount = 0;

        emit SwapBoxState(
            boxID,
            msg.sender,
            swapBoxes[boxID].state,
            swapBoxes[boxID].createdTime,
            block.timestamp,
            swapBoxes[boxID].gasTokenAmount,
            swapBoxes[boxID].erc721Tokens,
            swapBoxes[boxID].erc20Tokens,
            swapBoxes[boxID].erc1155Tokens
        );
    }

    // Link your Box to other's waiting Box. Equal to offer to other Swap Box
    function linkBox(uint256 listBoxID, uint256 offerBoxID)
        public
        isOpenForSwap
        nonReentrant
    {
        require(openSwap, "Swap is not opended");
        require(
            swapBoxes[offerBoxID].state == State.Offered,
            "Not Allowed Operation"
        );
        require(
            swapBoxes[offerBoxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );
        require(
            _existBoxID(swapBoxes[listBoxID], offerBoxID, true) == false,
            "This box is already linked"
        );

        require(
            swapBoxes[listBoxID].state == State.Waiting_for_offers,
            "This Box is not Waiting_for_offer State"
        );

        _putSwapOffer(offerBoxID, listBoxID, true);
        _putSwapOffer(listBoxID, offerBoxID, true);

        emit SwapBoxState(
            offerBoxID,
            msg.sender,
            State.Offered,
            swapBoxes[offerBoxID].createdTime,
            block.timestamp,
            swapBoxes[offerBoxID].gasTokenAmount,
            swapBoxes[offerBoxID].erc721Tokens,
            swapBoxes[offerBoxID].erc20Tokens,
            swapBoxes[offerBoxID].erc1155Tokens
        );
    }

    // Swaping Box. Owners of Each Swapbox should be exchanged
    function swapBox(uint256 listBoxID, uint256 offerBoxID)
        public
        isOpenForSwap
        nonReentrant
    {
        require(
            swapBoxes[listBoxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );
        require(
            swapBoxes[listBoxID].state == State.Waiting_for_offers,
            "Not Allowed Operation"
        );
        require(
            swapBoxes[offerBoxID].state == State.Offered,
            "Not offered Swap Box"
        );
        require(
            _existBoxID(swapBoxes[listBoxID], offerBoxID, true),
            "This box is not exist or active"
        );

        swapBoxes[listBoxID].owner = swapBoxes[offerBoxID].owner;
        swapBoxes[listBoxID].state = State.Initiated;
        delete swapBoxes[listBoxID].offers;

        swapBoxes[offerBoxID].owner = msg.sender;
        swapBoxes[offerBoxID].state = State.Initiated;
        delete swapBoxes[offerBoxID].offers;

        emit SwapBoxState(
            listBoxID,
            swapBoxes[listBoxID].owner,
            State.Initiated,
            swapBoxes[listBoxID].createdTime,
            block.timestamp,
            swapBoxes[listBoxID].gasTokenAmount,
            swapBoxes[listBoxID].erc721Tokens,
            swapBoxes[listBoxID].erc20Tokens,
            swapBoxes[listBoxID].erc1155Tokens
        );

        emit SwapBoxState(
            offerBoxID,
            swapBoxes[offerBoxID].owner,
            State.Initiated,
            swapBoxes[offerBoxID].createdTime,
            block.timestamp,
            swapBoxes[offerBoxID].gasTokenAmount,
            swapBoxes[offerBoxID].erc721Tokens,
            swapBoxes[offerBoxID].erc20Tokens,
            swapBoxes[offerBoxID].erc1155Tokens
        );

        emit Swaped(
            listBoxID,
            swapBoxes[listBoxID].owner,
            offerBoxID,
            swapBoxes[offerBoxID].owner
        );
    }

    // Cancel Listing. Box's state should be from Waiting_for_Offers to Initiate
    function deListBox(uint256 listBoxID) public isOpenForSwap nonReentrant {
        require(
            swapBoxes[listBoxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );
        require(
            swapBoxes[listBoxID].state == State.Waiting_for_offers,
            "Not Allowed Operation"
        );

        for (uint256 i = 0; i < swapBoxes[listBoxID].offers.length; i++) {
            if (
                swapBoxes[listBoxID].offers[i].active &&
                _existBoxID(
                    swapBoxes[swapBoxes[listBoxID].offers[i].boxID],
                    listBoxID,
                    true
                )
            ) {
                _putSwapOffer(
                    swapBoxes[listBoxID].offers[i].boxID,
                    listBoxID,
                    false
                );
            }
        }

        swapBoxes[listBoxID].state = State.Initiated;
        delete swapBoxes[listBoxID].offers;

        emit SwapBoxState(
            listBoxID,
            msg.sender,
            State.Initiated,
            swapBoxes[listBoxID].createdTime,
            block.timestamp,
            swapBoxes[listBoxID].gasTokenAmount,
            swapBoxes[listBoxID].erc721Tokens,
            swapBoxes[listBoxID].erc20Tokens,
            swapBoxes[listBoxID].erc1155Tokens
        );
    }

    // Cancel Offer. Box's state should be from Offered to Initiate
    function deOffer(uint256 offerBoxID) public isOpenForSwap nonReentrant {
        require(
            swapBoxes[offerBoxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );
        require(
            swapBoxes[offerBoxID].state == State.Offered,
            "Not Allowed Operation"
        );

        for (uint256 i = 0; i < swapBoxes[offerBoxID].offers.length; i++) {
            if (
                swapBoxes[offerBoxID].offers[i].active &&
                _existBoxID(
                    swapBoxes[swapBoxes[offerBoxID].offers[i].boxID],
                    offerBoxID,
                    true
                )
            ) {
                _putSwapOffer(
                    swapBoxes[offerBoxID].offers[i].boxID,
                    offerBoxID,
                    false
                );
            }
        }

        swapBoxes[offerBoxID].state = State.Initiated;
        delete swapBoxes[offerBoxID].offers;

        emit SwapBoxState(
            offerBoxID,
            msg.sender,
            State.Initiated,
            swapBoxes[offerBoxID].createdTime,
            block.timestamp,
            swapBoxes[offerBoxID].gasTokenAmount,
            swapBoxes[offerBoxID].erc721Tokens,
            swapBoxes[offerBoxID].erc20Tokens,
            swapBoxes[offerBoxID].erc1155Tokens
        );
    }

    // WithDraw offer from linked offer
    function deLink(uint256 listBoxID, uint256 offerBoxID)
        public
        isOpenForSwap
        nonReentrant
    {
        require(
            swapBoxes[offerBoxID].owner == msg.sender,
            "Allowed to only Owner of SwapBox"
        );
        require(
            swapBoxes[offerBoxID].state == State.Offered,
            "Not Allowed Operation"
        );
        require(
            _existBoxID(swapBoxes[listBoxID], offerBoxID, true),
            "This box is not linked"
        );
        require(
            _existBoxID(swapBoxes[offerBoxID], listBoxID, true),
            "This box is not linked"
        );

        _putSwapOffer(listBoxID, offerBoxID, false);
        _putSwapOffer(offerBoxID, listBoxID, false);

        emit SwapBoxState(
            offerBoxID,
            msg.sender,
            State.Initiated,
            swapBoxes[offerBoxID].createdTime,
            block.timestamp,
            swapBoxes[offerBoxID].gasTokenAmount,
            swapBoxes[offerBoxID].erc721Tokens,
            swapBoxes[offerBoxID].erc20Tokens,
            swapBoxes[offerBoxID].erc1155Tokens
        );
    }

    // Get Specific State Swap Boxed by Specific Wallet Address
    function getOwnedSwapBoxes(address boxOwner, State state)
        public
        view
        returns (SwapBox[] memory)
    {
        uint256 itemCount = 0;

        for (uint256 i = 1; i <= _itemCounter; i++) {
            if (swapBoxes[i].owner == boxOwner && swapBoxes[i].state == state) {
                itemCount++;
            }
        }

        SwapBox[] memory boxes = new SwapBox[](itemCount);
        uint256 itemIndex = 0;

        for (uint256 i = 1; i <= _itemCounter; i++) {
            if (swapBoxes[i].owner == boxOwner && swapBoxes[i].state == state) {
                boxes[itemIndex] = swapBoxes[i];
                itemIndex++;
            }
        }

        return boxes;
    }

    // Get offered Boxes to specifix box in Waiting_for_offer
    function getOfferedSwapBoxes(uint256 listBoxID)
        public
        view
        returns (SwapBox[] memory)
    {
        uint256 itemCount = 0;

        if (swapBoxes[listBoxID].state == State.Waiting_for_offers) {
            for (uint256 i = 0; i < swapBoxes[listBoxID].offers.length; i++) {
                if (
                    swapBoxes[listBoxID].offers[i].active &&
                    _existBoxID(
                        swapBoxes[swapBoxes[listBoxID].offers[i].boxID],
                        listBoxID,
                        true
                    )
                ) {
                    itemCount++;
                }
            }
        }

        SwapBox[] memory boxes = new SwapBox[](itemCount);
        uint256 itemIndex = 0;

        for (uint256 i = 0; i < swapBoxes[listBoxID].offers.length; i++) {
            if (
                swapBoxes[listBoxID].offers[i].active &&
                _existBoxID(
                    swapBoxes[swapBoxes[listBoxID].offers[i].boxID],
                    listBoxID,
                    true
                )
            ) {
                boxes[itemIndex] = swapBoxes[
                    swapBoxes[listBoxID].offers[i].boxID
                ];
                itemIndex++;
            }
        }

        return boxes;
    }

    // Get waiting Boxes what offered Box link to
    function getWaitingSwapBoxes(uint256 offerBoxID)
        public
        view
        returns (SwapBox[] memory)
    {
        uint256 itemCount = 0;

        if (swapBoxes[offerBoxID].state == State.Offered) {
            for (uint256 i = 0; i < swapBoxes[offerBoxID].offers.length; i++) {
                if (
                    swapBoxes[offerBoxID].offers[i].active &&
                    _existBoxID(
                        swapBoxes[swapBoxes[offerBoxID].offers[i].boxID],
                        offerBoxID,
                        true
                    )
                ) {
                    itemCount++;
                }
            }
        }

        SwapBox[] memory boxes = new SwapBox[](itemCount);
        uint256 itemIndex = 0;

        for (uint256 i = 0; i < swapBoxes[offerBoxID].offers.length; i++) {
            if (
                swapBoxes[offerBoxID].offers[i].active &&
                _existBoxID(
                    swapBoxes[swapBoxes[offerBoxID].offers[i].boxID],
                    offerBoxID,
                    true
                )
            ) {
                boxes[itemIndex] = swapBoxes[
                    swapBoxes[offerBoxID].offers[i].boxID
                ];
                itemIndex++;
            }
        }

        return boxes;
    }

    // Get Swap Box by Index
    function getBoxByIndex(uint256 listBoxID)
        public
        view
        returns (SwapBox memory)
    {
        return swapBoxes[listBoxID];
    }

    // Get specific state of Swap Boxes
    function getBoxesByState(State state)
        public
        view
        returns (SwapBox[] memory)
    {
        uint256 itemCount = 0;

        for (uint256 i = 1; i <= _itemCounter; i++) {
            if (swapBoxes[i].state == state) {
                itemCount++;
            }
        }

        SwapBox[] memory boxes = new SwapBox[](itemCount);
        uint256 itemIndex = 0;

        for (uint256 i = 1; i <= _itemCounter; i++) {
            if (swapBoxes[i].state == state) {
                boxes[itemIndex] = swapBoxes[i];
                itemIndex++;
            }
        }

        return boxes;
    }
}
