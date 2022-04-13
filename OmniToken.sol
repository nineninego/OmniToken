// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./NonblockingReceiver.sol";

interface iOxMosquitoes {
    function ownerOf(uint256 tokenid) external view returns (address owner);
}

contract OmniBlood is Ownable, ERC20, NonblockingReceiver {

    iOxMosquitoes immutable OxMosquitoes;
    uint256 gasForDestinationLzReceive = 350000;

    // claimable once on every chain
    uint256 constant public rate = 1000 ether;
    mapping(uint256 => bool) public claimed;

    constructor(address _OxMosquitoes, address _layerZeroEndpoint) ERC20("OmniBlood", "OMB") {
        OxMosquitoes = iOxMosquitoes(_OxMosquitoes);
        endpoint = ILayerZeroEndpoint(_layerZeroEndpoint);
    }

    function claim(uint256 _tokenId) public {
        require(
            OxMosquitoes.ownerOf(_tokenId) == msg.sender, 
            "omni blood: owner"
        );
        require(
            !claimed[_tokenId], 
            "omni blood: already claimed"
        );
        claimed[_tokenId] = true;
        _mint(msg.sender, rate);
    }

    function claimMulti(uint256[] calldata _tokenids) external {
        uint256 l = _tokenids.length;
        for(uint256 i = 0; i < l; i++) {
            claim(_tokenids[i]);
        }
    }

    function traverseChains(uint16 _chainId, uint256 _amount) public payable {
        require(
            trustedRemoteLookup[_chainId].length > 0, 
            "omni blood: this chain is currently unavailable for travel"
        );
        require(
            _amount > 0, 
            "omni blood: amount is 0"
        );

        // burn, eliminating it from circulation on src chain
        _burn(msg.sender, _amount);

        // abi.encode() the payload with the values to send
        bytes memory payload = abi.encode(msg.sender, _amount);

        // encode adapterParams to specify more gas for the destination
        uint16 version = 1;
        bytes memory adapterParams = abi.encodePacked(
            version,
            gasForDestinationLzReceive
        );

        // get the fees we need to pay to LayerZero + Relayer to cover message delivery
        // you will be refunded for extra gas paid
        (uint256 messageFee, ) = endpoint.estimateFees(
            _chainId,
            address(this),
            payload,
            false,
            adapterParams
        );

        require(
            msg.value >= messageFee,
            "omni blood: msg.value not enough to cover messageFee. Send gas for message fees"
        );

        endpoint.send{value: msg.value}(
            _chainId, // destination chainId
            trustedRemoteLookup[_chainId], // destination address of nft contract
            payload, // abi.encoded()'ed bytes
            payable(msg.sender), // refund address
            address(0x0), // 'zroPaymentAddress' unused for this
            adapterParams // txParameters
        );
    }

    function setGasForDestinationLzReceive(uint256 _newVal) external onlyOwner {
        gasForDestinationLzReceive = _newVal;
    }

    function donate() external payable {
        // thank you
    }

    // This allows the dev to receive kind donations
    function withdraw() external onlyOwner {
        (bool sent, ) = payable(owner()).call{value: address(this).balance}("");
        require(
            sent, 
            "omni blood: Failed to withdraw Ether"
        );
    }

    function _LzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal override {
        // decode
        (address _to, uint256 _amount) = abi.decode(
            _payload,
            (address, uint256)
        );

        // mint the tokens back into existence on destination chain
        _mint(_to, _amount);
    }
}
