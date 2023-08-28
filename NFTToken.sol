// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./Ownable.sol";
import "./SafeMath.sol";

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract NFTToken is ERC721, Ownable {

    using SafeMath for uint256;

    uint256 public totalNFTs;

    constructor() ERC721("NFTToken", "NFT") {}

    function mintNFT(address to, string memory tokenURI) public onlyOwner {
        uint256 tokenId = totalNFTs;
        _mint(to, tokenId);
        setTokenURI(tokenId, tokenURI);
        totalNFTs = totalNFTs.add(1);
    }

    function setTokenURI(uint256 tokenId, string memory tokenURI) public onlyOwner {
        require(_exists(tokenId), "Token does not exist");
        setTokenURI(tokenId, tokenURI);
    }

    function mint(address to, uint256 tokenId) external onlyOwner {
        _mint(to, tokenId);
    }

    function tokenExists(uint256 tokenId) public view returns (bool) {
        return _exists(tokenId);
    }

}