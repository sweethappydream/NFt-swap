// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC721/IERC721.sol)

pragma solidity ^0.8.0;
interface IERC721{
    function balanceOf(address owner) external view returns (uint256 balance);
    function safeTransferFrom(address from,address to,uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function safeTransferFrom(address from,address to,uint256 tokenId,bytes calldata data) external;
}
