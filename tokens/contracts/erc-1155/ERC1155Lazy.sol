// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@rarible/royalties/contracts/impl/RoyaltiesV2Impl.sol";
import "@rarible/royalties-upgradeable/contracts/RoyaltiesV2Upgradeable.sol";
import "@rarible/lazy-mint/contracts/erc-1155/IERC1155LazyMint.sol";
import "./Mint1155Validator.sol";
import "./ERC1155BaseURI.sol";

abstract contract ERC1155Lazy is IERC1155LazyMint, ERC1155BaseURI, Mint1155Validator, RoyaltiesV2Upgradeable, RoyaltiesV2Impl {
    using SafeMathUpgradeable for uint;

    mapping (uint256 => LibPart.Part[]) public creators;
    mapping (uint => uint) private supply;
    mapping (uint => uint) private minted;

    function __ERC1155Lazy_init_unchained() internal initializer {
        _registerInterface(0x6db15a0f);
    }

    function transferFromOrMint(
        LibERC1155LazyMint.Mint1155Data memory data,
        address from,
        address to,
        uint256 amount
    ) override external {
        uint balance = balanceOf(from, data.tokenId);
        uint left = amount;
        if (balance != 0) {
            uint transfer = amount;
            if (balance < amount) {
                transfer = balance;
            }
            safeTransferFrom(from, to, data.tokenId, transfer, "");
            left = amount - transfer;
        }
        if (left > 0) {
            mintAndTransfer(data, to, left);
        }
    }

    function mintAndTransfer(LibERC1155LazyMint.Mint1155Data memory data, address to, uint256 _amount) public override virtual {
        address minter = address(data.tokenId >> 96);
        address sender = _msgSender();

        require(minter == sender || isApprovedForAll(minter, sender), "ERC1155: transfer caller is not approved");
        require(_amount > 0, "amount incorrect");
        //todo эти проверки актуальны в ифе if (supply[data.tokenId] == 0). можно их туда перенести?
        require(data.creators.length == data.signatures.length);
        require(data.supply > 0, "supply incorrect");
        require(bytes(data.uri).length > 0, "uri should be set");
        //это тоже актуально только в ифе. т к только в нем проверяются creators. значит можно хоть что подставить
        //при повторном lazy минт, а значит эта проверка не имеет смысла
        require(minter == data.creators[0].account, "tokenId incorrect");

        if (supply[data.tokenId] == 0) {
            for (uint i = 0; i < data.creators.length; i++) {
                //todo хэш от даты LibERC1155LazyMint.hash(data) вычисляется для каждого creator-а,
                //  при этом она одинакова для всех. это довольно затрано
                //  можно ли вычислить здесь один раз и передавать параметром в эту функцию?
                //  для ERC721Lazy такой же вопрос
                validate(sender, data, i);
            }

            _saveSupply(data.tokenId, data.supply);
            _saveRoyalties(data.tokenId, data.royalties);
            _saveCreators(data.tokenId, data.creators);
            _setTokenURI(data.tokenId, data.uri);
        }

        //т е при повторных lazy созданиях участвуют только значения: tokenId, to, amount. minter по tokenId д б sender-ом или minter апрувнул sender-а
        //остальные поля не участвуют и могут быть абсолютно любыми или вообще пустыми: creators, signatures, supply, uri, royalties
        _mint(to, data.tokenId, _amount, "");
    }

    function _mint(address account, uint256 id, uint256 amount, bytes memory data) internal virtual override {
        uint newMinted = amount.add(minted[id]);
        require(newMinted <= supply[id], "more than supply");
        minted[id] = newMinted;
        super._mint(account, id, amount, data);
    }

    function _saveSupply(uint tokenId, uint _supply) internal {
        require(supply[tokenId] == 0);
        supply[tokenId] = _supply;
        emit Supply(tokenId, _supply);
    }

    function _saveCreators(uint tokenId, LibPart.Part[] memory _creators) internal {
        LibPart.Part[] storage creatorsOfToken = creators[tokenId];
        uint total = 0;
        for(uint i=0; i < _creators.length; i++) {
            require(_royalties[i].account != address(0x0), "Recipient should be present");//todo такие проверки надо? как в роялтиз
            require(_royalties[i].value != 0, "Royalty value should be positive");
            creatorsOfToken.push(_creators[i]);
            total = total.add(_creators[i].value);
        }
        require(total == 10000, "total amount of creators share should be 10000");
        emit Creators(tokenId, _creators);
    }

    function getCreators(uint256 _id) external view returns (LibPart.Part[] memory) {
        return creators[_id];
    }
    uint256[50] private __gap;
}
