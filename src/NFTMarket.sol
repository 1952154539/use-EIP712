// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title NFTMarket - NFT marketplace with EIP-712 whitelist buying
/// @notice Only whitelisted addresses (signed by contract owner) can purchase NFTs
contract NFTMarket is Ownable {
    using ECDSA for bytes32;

    IERC721 public immutable nft;
    IERC20 public immutable paymentToken;

    // EIP-712 typehash for WhitelistPermit
    bytes32 private constant WHITELIST_PERMIT_TYPEHASH =
        keccak256(
            "WhitelistPermit(address buyer,uint256 tokenId,uint256 price,uint256 deadline)"
        );

    // Track used permits to prevent replay
    mapping(bytes32 => bool) public usedPermits;

    // Track listed NFTs: tokenId => (seller, price)
    struct Listing {
        address seller;
        uint256 price;
        bool active;
    }
    mapping(uint256 => Listing) public listings;

    event Listed(uint256 indexed tokenId, address indexed seller, uint256 price);
    event Purchased(uint256 indexed tokenId, address indexed buyer, address indexed seller, uint256 price);
    event Delisted(uint256 indexed tokenId);

    constructor(address _nft, address _paymentToken) Ownable(msg.sender) {
        nft = IERC721(_nft);
        paymentToken = IERC20(_paymentToken);
    }

    /// @notice List an NFT for sale. Seller must approve NFT to this contract first.
    function list(uint256 tokenId, uint256 price) external {
        require(price > 0, "Price must be > 0");
        require(
            nft.ownerOf(tokenId) == msg.sender,
            "Not NFT owner"
        );
        require(
            nft.getApproved(tokenId) == address(this) ||
                nft.isApprovedForAll(msg.sender, address(this)),
            "Market not approved"
        );

        listings[tokenId] = Listing({
            seller: msg.sender,
            price: price,
            active: true
        });
        emit Listed(tokenId, msg.sender, price);
    }

    /// @notice Delist an NFT
    function delist(uint256 tokenId) external {
        Listing storage listing = listings[tokenId];
        require(listing.active, "Not listed");
        require(listing.seller == msg.sender, "Not seller");
        listing.active = false;
        emit Delisted(tokenId);
    }

    /// @notice Normal purchase: buyer must approve paymentToken first
    function buy(uint256 tokenId) external {
        Listing memory listing = listings[tokenId];
        require(listing.active, "Not listed");
        require(listing.seller != msg.sender, "Cannot buy own NFT");

        listings[tokenId].active = false;

        // Transfer payment from buyer to seller
        require(
            paymentToken.transferFrom(msg.sender, listing.seller, listing.price),
            "Payment failed"
        );

        // Transfer NFT from seller to buyer
        nft.safeTransferFrom(listing.seller, msg.sender, tokenId);

        emit Purchased(tokenId, msg.sender, listing.seller, listing.price);
    }

    /// @notice Whitelist purchase using EIP-712 signature
    /// @dev Only addresses with a valid signature from the contract owner can buy
    /// @param buyer The address authorized to buy (must be msg.sender or relayer)
    /// @param tokenId The NFT token ID to purchase
    /// @param price The purchase price
    /// @param deadline Signature expiration timestamp
    /// @param v Signature v
    /// @param r Signature r
    /// @param s Signature s
    function permitBuy(
        address buyer,
        uint256 tokenId,
        uint256 price,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= deadline, "Permit expired");
        require(buyer == msg.sender, "Not authorized buyer");

        // Reconstruct the EIP-712 typed data hash
        bytes32 structHash = keccak256(
            abi.encode(
                WHITELIST_PERMIT_TYPEHASH,
                buyer,
                tokenId,
                price,
                deadline
            )
        );

        bytes32 domainSeparator = _buildDomainSeparator();
        bytes32 digest = MessageHashUtils.toTypedDataHash(domainSeparator, structHash);

        // Recover signer from signature
        address signer = ECDSA.recover(digest, v, r, s);

        // Only contract owner can authorize whitelist purchases
        require(signer == owner(), "Invalid whitelist signature");

        // Prevent signature replay
        bytes32 permitHash = keccak256(abi.encodePacked(buyer, tokenId, deadline));
        require(!usedPermits[permitHash], "Permit already used");
        usedPermits[permitHash] = true;

        // Execute purchase
        Listing memory listing = listings[tokenId];
        require(listing.active, "Not listed");
        require(listing.seller != buyer, "Cannot buy own NFT");
        require(listing.price == price, "Price mismatch");

        listings[tokenId].active = false;

        // Transfer payment from buyer to seller
        require(
            paymentToken.transferFrom(buyer, listing.seller, price),
            "Payment failed"
        );

        // Transfer NFT from seller to buyer
        nft.safeTransferFrom(listing.seller, buyer, tokenId);

        emit Purchased(tokenId, buyer, listing.seller, price);
    }

    /// @notice Build the EIP-712 domain separator for this contract
    function _buildDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    keccak256(
                        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                    ),
                    keccak256(bytes("NFTMarket")),
                    keccak256(bytes("1")),
                    block.chainid,
                    address(this)
                )
            );
    }

    /// @notice Public helper to compute the domain separator
    function DOMAIN_SEPARATOR() external view returns (bytes32) {
        return _buildDomainSeparator();
    }

    /// @notice Compute the permit hash for a given buyer/tokenId/deadline
    function getPermitHash(
        address buyer,
        uint256 tokenId,
        uint256 price,
        uint256 deadline
    ) external view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                WHITELIST_PERMIT_TYPEHASH,
                buyer,
                tokenId,
                price,
                deadline
            )
        );
        return MessageHashUtils.toTypedDataHash(_buildDomainSeparator(), structHash);
    }
}
