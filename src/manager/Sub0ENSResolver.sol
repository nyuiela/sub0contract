// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title Sub0ENSResolver
 * @notice CCIP-Read offchain resolver for sub0.eth subnames.
 *
 * Implements EIP-3668 (CCIP-Read) so that agents get gasless ENS subnames
 * (e.g. bullish-scout-1.sub0.eth) resolved by the Sub0 backend gateway.
 *
 * Deployment:
 *   1. Deploy this contract.
 *   2. Set the ENS resolver for sub0.eth to point to this contract.
 *   3. The contract emits OffchainLookup directing callers to the backend.
 *
 * Backend gateway: /api/ens/resolve?name={name}&sender={sender}
 * Response: ABI-encoded (address addr, uint64 expiry, bytes sig)
 * The backend signs keccak256(abi.encode(name, addr, expiry)) with BACKEND_SIGNER_KEY.
 */

interface IResolverCallback {
    function resolveWithProof(bytes calldata response, bytes calldata extraData)
        external
        view
        returns (bytes memory);
}

/**
 * @dev Thrown by EIP-3668: tells clients to fetch data from gateway URLs.
 */
error OffchainLookup(
    address sender,
    string[] urls,
    bytes callData,
    bytes4 callbackFunction,
    bytes extraData
);

contract Sub0ENSResolver {
    /// @notice Address authorised to update the gateway URL and signer.
    address public immutable owner;

    /// @notice Backend gateway URL for CCIP-Read lookups.
    string public gatewayUrl;

    /// @notice Address whose ECDSA signature validates resolved addresses.
    address public signerAddress;

    event GatewayUrlUpdated(string newUrl);
    event SignerAddressUpdated(address newSigner);

    constructor(string memory _gatewayUrl, address _signerAddress) {
        owner = msg.sender;
        gatewayUrl = _gatewayUrl;
        signerAddress = _signerAddress;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Sub0ENSResolver: not owner");
        _;
    }

    function setGatewayUrl(string calldata _url) external onlyOwner {
        gatewayUrl = _url;
        emit GatewayUrlUpdated(_url);
    }

    function setSignerAddress(address _signer) external onlyOwner {
        require(_signer != address(0), "Sub0ENSResolver: zero signer");
        signerAddress = _signer;
        emit SignerAddressUpdated(_signer);
    }

    /**
     * @notice Resolve an ENS name to an address via CCIP-Read.
     * @dev Reverts with OffchainLookup so the client fetches from the gateway.
     *      After fetching, the client calls resolveWithProof() with the response.
     * @param name The DNS-encoded ENS name to resolve.
     */
    function resolve(bytes calldata name) external view returns (bytes memory) {
        bytes memory callData = abi.encodeWithSelector(
            IResolverCallback.resolveWithProof.selector,
            name
        );
        string[] memory urls = new string[](1);
        urls[0] = string(abi.encodePacked(
            gatewayUrl,
            "?name={sender}&sender={sender}"
        ));
        revert OffchainLookup(
            address(this),
            urls,
            callData,
            IResolverCallback.resolveWithProof.selector,
            name
        );
    }

    /**
     * @notice Callback invoked after client fetches from the gateway.
     * @param response ABI-encoded (address addr, uint64 expiry, bytes sig).
     * @param extraData The original DNS-encoded name (passed as extraData in OffchainLookup).
     * @return ABI-encoded address of the resolved agent wallet.
     */
    function resolveWithProof(bytes calldata response, bytes calldata extraData)
        external
        view
        returns (bytes memory)
    {
        (address addr, uint64 expiry, bytes memory sig) =
            abi.decode(response, (address, uint64, bytes));

        require(block.timestamp <= expiry, "Sub0ENSResolver: signature expired");

        // Recover signer from sig over keccak256(name, addr, expiry)
        string memory name = _decodeDnsName(extraData);
        bytes32 msgHash = keccak256(
            abi.encodePacked(name, addr, expiry)
        );
        bytes32 ethHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash)
        );
        address recovered = _recoverSigner(ethHash, sig);
        require(recovered == signerAddress, "Sub0ENSResolver: invalid signature");

        return abi.encode(addr);
    }

    /**
     * @dev Minimal DNS name decoder: returns the human-readable name.
     *      e.g. [7]bullish[4]sub0[3]eth[0] -> "bullish.sub0.eth"
     */
    function _decodeDnsName(bytes calldata data) internal pure returns (string memory) {
        bytes memory out;
        uint256 i = 0;
        while (i < data.length) {
            uint8 labelLen = uint8(data[i]);
            if (labelLen == 0) break;
            if (out.length > 0) out = abi.encodePacked(out, ".");
            out = abi.encodePacked(out, data[i + 1 : i + 1 + labelLen]);
            i += 1 + labelLen;
        }
        return string(out);
    }

    /**
     * @dev Recover signer from an Ethereum personal-signed hash.
     */
    function _recoverSigner(bytes32 hash, bytes memory sig)
        internal
        pure
        returns (address)
    {
        require(sig.length == 65, "Sub0ENSResolver: bad sig length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
        if (v < 27) v += 27;
        return ecrecover(hash, v, r, s);
    }

    /**
     * @notice Check if this contract supports a given interface (ERC-165).
     */
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IResolverCallback).interfaceId
            || interfaceId == 0x01ffc9a7; // ERC-165
    }
}
