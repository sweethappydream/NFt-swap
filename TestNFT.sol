// contracts/TestNFT.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";

contract TestNFT is ERC721 {
    using Strings for uint256;

    uint256 private _currentTokenId = 0; //tokenId will start from 1
    string public baseURI_ = "";

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {
        
    }

    /**
     * @dev Mints a token to an address with a tokenURI.
     * @param _to address of the future owner of the token
     */
    function mintTo(address _to) public {
        uint256 newTokenId = _getNextTokenId();
        _mint(_to, newTokenId);
        _incrementTokenId();
    }

    /**
     * @dev calculates the next token ID based on value of _currentTokenId
     * @return uint256 for the next token ID
     */
    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId + 1;
    }

    /**
     * @dev increments the value of _currentTokenId
     */
    function _incrementTokenId() private {
        _currentTokenId ++;
    }

    /**
     * @dev Set BaseURI 
     */
    function setBaseURI(string memory baseURI) public {
        baseURI_ = baseURI;
    }

    /*
     * Function to Get TokenURI
     */
    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(
            _exists(tokenId),
            "ERC721METADATA: URI query for non existent token"
        );

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name": "',
                                name(),
                                '#',
                                tokenId.toString(),
                                '", "image":"',
                                baseURI_,
                                tokenId.toString(),
                                '.png"}'
                            )
                        )
                    )
                )
            );
    }

}
