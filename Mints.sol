// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

// Base64 library to base64 encode the tokenURI
import {Base64} from "./base64.sol";

// Nouns (nouns.wtf) library to create svgs out of the seed parts
import {MultiPartRLEToSVG} from "./MultiPartRLEToSVG.sol";

contract Mints is Ownable, ERC721Pausable, ERC721Enumerable {
    using Strings for uint256;

    struct Seed {
        uint48 body;
        uint48 face;
        uint48 eyes;
        uint48 mouth;
    }

    // Mapping for all seeds
    mapping(uint256 => Seed) private _seeds;

    // 1111 unique mints
    uint256 private MAX_AMOUNT = 1111;

    // 20 MATIC
    uint256 private PRICE = 20 ether;

    // Tracks the current token id to use for the next mint
    uint256 private _tokenIdTracker = 0;

    // Color palettes (index => hex Colors)
    mapping(uint8 => string[]) private palettes;

    // Bodies (Nouns custom RLE)
    bytes[] private bodies;

    // Faces (Nouns custom RLE)
    bytes[] private faces;

    // Eyes (Nouns custom RLE)
    bytes[] private eyes;

    // Mouths (Nouns custom RLE)
    bytes[] private mouths;

    bool private _partsLocked = false;

    error Unauthorized();
    error SoldOut();
    error NotFound();

    constructor() ERC721("MINTS", "MTS") {}

    function setParts(
        bytes[] memory _bodies,
        bytes[] memory _faces,
        bytes[] memory _eyes,
        bytes[] memory _mouths,
        string[] memory palette
    ) external onlyOwner {
        // check if parts have been locked
        if (_partsLocked == true) {
            revert Unauthorized();
        }

        bodies = _bodies;
        faces = _faces;
        eyes = _eyes;
        mouths = _mouths;

        palettes[0] = palette;

        // lock parts after uploading
        _partsLocked = true;
    }

    /**
     * @notice Generate a pseudo-random Seed using the previous blockhash and tokenId.
     */
    // prettier-ignore
    function _generateSeed(uint256 tokenId) private view returns (Seed memory) {
        uint256 pseudorandomness = uint256(
            keccak256(abi.encodePacked(blockhash(block.number - 1), tokenId))
        );

        uint256 bodyCount = bodies.length;
        uint256 faceCount = faces.length;
        uint256 mouthCount = mouths.length;
        uint256 eyesCount = eyes.length;

        return Seed({
            body: uint48(
                uint48(pseudorandomness) % bodyCount
            ),
            face: uint48(
                uint48(pseudorandomness >> 48) % faceCount
            ),
            mouth: uint48(
                uint48(pseudorandomness >> 96) % mouthCount
            ),
            eyes: uint48(
                uint48(pseudorandomness >> 144) % eyesCount
            )
        });
    }

    function withdraw() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @notice Mints a MINT and generates a new seed.
     */
    function mint() external payable whenNotPaused {
        // Make sure not everything has been minted
        if (_tokenIdTracker == MAX_AMOUNT) {
            revert SoldOut();
        }

        // Check the sent value
        if (msg.value != PRICE) {
            revert Unauthorized();
        }

        // mint
        _safeMint(msg.sender, _tokenIdTracker);

        // generate seed
        Seed memory seed = _generateSeed(_tokenIdTracker);

        // save seed
        _seeds[_tokenIdTracker] = seed;

        // update token
        _tokenIdTracker += 1;
    }

    /**
     * @notice Generates a svg using the MultiPartRLEToSVG library
     */
    function _generateSVG(bytes[] memory parts)
        private
        view
        returns (string memory)
    {
        return
            Base64.encode(
                bytes(MultiPartRLEToSVG.generateSVG(parts, palettes))
            );
    }

    /**
     * @notice Get all parts for the passed `seed`.
     */
    function _getPartsForSeed(Seed memory seed)
        private
        view
        returns (bytes[] memory)
    {
        bytes[] memory _parts = new bytes[](4);
        _parts[0] = bodies[seed.body];
        _parts[1] = faces[seed.face];
        _parts[2] = eyes[seed.eyes];
        _parts[3] = mouths[seed.mouth];
        return _parts;
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        // Throw error if id does not exist
        if (!_exists(id)) {
            revert NotFound();
        }

        // read the seed and get its parts
        bytes[] memory parts = _getPartsForSeed(_seeds[id]);

        // return a base64 encoded json file containing all the data
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name": "MINT #',
                                id.toString(),
                                '", "description":"',
                                "MINTS is a NFT project that lets you mint a MINT.",
                                '", "image": "',
                                "data:image/svg+xml;base64,",
                                _generateSVG(parts),
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721Pausable, ERC721Enumerable) whenNotPaused {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
