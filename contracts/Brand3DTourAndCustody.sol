// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

// for custody
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Sender.sol";
import "@openzeppelin/contracts/token/ERC777/IERC777Recipient.sol";
import "@openzeppelin/contracts/utils/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract Brand3DTourAndCustody is
  ERC721URIStorage,
  ERC721Enumerable,
  IERC777Sender,
  IERC777Recipient,
  IERC721Receiver,
  Ownable,
  AccessControl
{
  struct RentedNFT {
    address previousOwner;
    uint256 tokenId;
    uint256 timeLockExpiry;
  }

  struct TourStake {
    address previousOwner;
    uint256 numberOfTokens;
  }

  // Create a new role identifier for the minter role
  bytes32 public constant WHITELISTED_ROLE = keccak256("WHITELISTED_ROLE");

  // Registering with ERC1820 Registry that we can recieve ERC777
  IERC1820Registry private _erc1820 =
    IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
  bytes32 private constant TOKENS_RECIPIENT_INTERFACE_HASH =
    keccak256("ERC777TokensRecipient");

  bytes4 private ERC721_SELECTOR =
    bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));

  uint256 public TOUR_ENTRY_FEE = 30 * (10**18);
  IERC777 public token;

  bool hasTourClosed;

  // renting state
  RentedNFT[] public rents;
  address[] public lookupTable;
  mapping(address => TourStake) public stake;
  uint256 public numberOfTokensStaked;
  uint256 public totalFeesCollected;

  // user entry state
  mapping(address => bool) hasEntered;

  event EnteredTour(address indexed person, address indexed tour);

  modifier onlyWhitelisted() {
    require(hasRole(WHITELISTED_ROLE, msg.sender)); // , "Caller is not whitelisted");
    _;
  }

  constructor(string memory _name, string memory _symbol)
    ERC721(_name, _symbol)
  {
    _erc1820.setInterfaceImplementer(
      address(this),
      TOKENS_RECIPIENT_INTERFACE_HASH,
      address(this)
    );
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
  }

  // ERC721 functions
  function mint(
    address _to,
    uint256 _tokenId,
    string memory _tokenURI
  ) external {
    _safeMint(_to, _tokenId);
    _setTokenURI(_tokenId, _tokenURI);
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 tokenId
  ) internal virtual override(ERC721, ERC721Enumerable) {
    super._beforeTokenTransfer(from, to, tokenId);
  }

  function _burn(uint256 tokenId)
    internal
    virtual
    override(ERC721, ERC721URIStorage)
  {
    super._burn(tokenId);
  }

  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override(ERC721, ERC721Enumerable, AccessControl)
    returns (bool)
  {
    return super.supportsInterface(interfaceId);
  }

  function tokenURI(uint256 tokenId)
    public
    view
    virtual
    override(ERC721, ERC721URIStorage)
    returns (string memory)
  {
    return super.tokenURI(tokenId);
  }

  // custody functions
  function addWhitelistedUser(address _address) external onlyOwner {
    _grantRole(WHITELISTED_ROLE, _address);
  }

  function hasEnteredTour(address _address) external view returns (bool) {
    return hasEntered[_address];
  }

  function getRents() external view returns (RentedNFT[] memory) {
    return rents;
  }

  function getEstimatedRewards(address _address)
    external
    view
    returns (uint256)
  {
    if (totalFeesCollected == 0) return 0;
    if (numberOfTokensStaked == 0) return 0;

    uint256 numberOfTokens = stake[_address].numberOfTokens;
    return totalFeesCollected * (numberOfTokens / numberOfTokensStaked);
  }

  function canRedeemNFT(address _address) external view returns (bool) {
    for (uint256 i = 0; i < rents.length; i++) {
      if (rents[i].previousOwner == _address) {
        return true;
      }
    }

    return false;
  }

  function canRedeemNFT(address _address, uint256 _tokenId)
    external
    view
    returns (bool)
  {
    for (uint256 i = 0; i < rents.length; i++) {
      if (rents[i].previousOwner == _address && rents[i].tokenId == _tokenId) {
        return true;
      }
    }

    return false;
  }

  function setTokenAddress(address _token) external onlyOwner {
    token = IERC777(_token);
  }

  function enterTour() external {
    require(!hasEntered[msg.sender]); // , "Already entered tour");
    require(!hasTourClosed);
    hasEntered[msg.sender] = true;
    totalFeesCollected = totalFeesCollected + TOUR_ENTRY_FEE;
    token.operatorSend(msg.sender, address(this), TOUR_ENTRY_FEE, "", "");
    emit EnteredTour(msg.sender, address(this));
  }

  function onERC721Received(
    address,
    address _from,
    uint256 _tokenId,
    bytes calldata //_data
  ) external override(IERC721Receiver) returns (bytes4) {
    require(hasRole(WHITELISTED_ROLE, _from));
    require(!hasTourClosed);

    RentedNFT memory newRent = RentedNFT({
      previousOwner: _from,
      tokenId: _tokenId,
      timeLockExpiry: block.timestamp + (14 * 86400) // 2 WEEKS
    });

    rents.push(newRent);

    if (stake[_from].previousOwner == _from) {
      stake[_from] = TourStake({
        previousOwner: _from,
        numberOfTokens: stake[_from].numberOfTokens + 1
      });
    } else {
      lookupTable.push(_from);
      stake[_from] = TourStake({ previousOwner: _from, numberOfTokens: 1 });
    }

    numberOfTokensStaked++;

    return ERC721_SELECTOR;
  }

  function redeemRewards() public onlyWhitelisted {
    for (uint256 i = 0; i < lookupTable.length; i++) {
      uint256 numberOfTokens = stake[lookupTable[i]].numberOfTokens;
      token.send(
        lookupTable[i],
        totalFeesCollected * (numberOfTokens / numberOfTokensStaked),
        ""
      );
    }

    totalFeesCollected = 0;
  }

  function redeemNFT(uint256 _tokenId) external onlyWhitelisted {
    bool didTransfer = false;
    for (uint256 i = 0; i < rents.length; i++) {
      if (
        rents[i].previousOwner == msg.sender && rents[i].tokenId == _tokenId
      ) {
        require(rents[i].timeLockExpiry < block.timestamp);
        safeTransferFrom(address(this), msg.sender, rents[i].tokenId);
        didTransfer = true;
      }
    }

    require(didTransfer); // , "This NFT was not rented or the owner is incorrect");

    stake[msg.sender] = TourStake({
      previousOwner: msg.sender,
      numberOfTokens: stake[msg.sender].numberOfTokens - 1
    });

    if (stake[msg.sender].numberOfTokens == 0) {
      for (uint256 i = 0; i < lookupTable.length; i++) {
        if (lookupTable[i] == msg.sender) {
          lookupTable[i] = lookupTable[lookupTable.length - 1];
          break;
        }
      }
      lookupTable.pop();
    }
  }

  function redeemAllNFTs() external onlyWhitelisted {
    require(hasTourClosed);

    bool didTransfer = false;
    for (uint256 i = 0; i < rents.length; i++) {
      if (rents[i].previousOwner == msg.sender) {
        require(rents[i].timeLockExpiry < block.timestamp);
        safeTransferFrom(address(this), msg.sender, rents[i].tokenId);
        didTransfer = true;
      }
    }

    require(didTransfer); // , "Owner hasn't rented any NFTs to the tour!");

    delete stake[msg.sender];

    for (uint256 i = 0; i < lookupTable.length; i++) {
      if (lookupTable[i] == msg.sender) {
        lookupTable[i] = lookupTable[lookupTable.length - 1];
        break;
      }
    }
    lookupTable.pop();
  }

  function closeTour() public onlyWhitelisted {
    redeemRewards();

    for (uint256 i = 0; i < rents.length; i++) {
      safeTransferFrom(address(this), rents[i].previousOwner, rents[i].tokenId);
    }

    hasTourClosed = true;

    for (uint256 i = 0; i < lookupTable.length; i++) {
      delete stake[lookupTable[i]];
    }

    delete rents;
    delete lookupTable;
  }

  function restartTour() external onlyWhitelisted {
    hasTourClosed = false;
  }

  // code to conform to ERC777TokensRecipient
  function tokensReceived(
    address operator,
    address from,
    address to,
    uint256 amount,
    bytes calldata userData,
    bytes calldata operatorData
  ) external override(IERC777Recipient) {}

  function tokensToSend(
    address operator,
    address from,
    address to,
    uint256 amount,
    bytes calldata userData,
    bytes calldata operatorData
  ) external override(IERC777Sender) {}
}
