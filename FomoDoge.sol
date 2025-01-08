// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "erc721a/contracts/ERC721A.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract FomoDoge is ERC721A("FomoDoge", "FomoDoge"), Ownable, ReentrancyGuard{
    using Address for address payable;
    using Strings for uint256;

    address private _protocol;

    string private baseURI = "https://www.fomodoge.com/uri/";

    string public Web = "https://fomodoge.com";
    string public X = "https://x.com/FomoDogeX";
    string public Telegram = "https://t.me/FomodogeETH";

    mapping(address => uint) public usrBalance;
    mapping(uint => uint) public unlockTime;
    mapping(address => uint) public usrBalanceForShare;
    mapping(address => uint) public inviteTotal;
    uint private _basePrice = 1e15; 
    uint private _step = 26315e9;

    uint public liqPool;
    uint public fomoPool;
    uint public endTime;
    uint public fomoPoolForEach;
    address[5] private _winners;

    event Buy(address indexed usr, address indexed inviter, uint amount, uint indexed value);
    event Sell(address indexed usr, uint amount, uint value);
    event FOMO(address winner1, address winner2, address winner3, address winner4, address winner5, uint fomopool, bool isEnded);

    constructor() Ownable(msg.sender){
        endTime = block.timestamp + 86400;
        _protocol = msg.sender;
    }

    function buy(uint amount, uint lockType, address inviteAddress)public payable nonReentrant{
        require(balanceOf(msg.sender) + amount <= 500, "Exceed The maximum number of a single address");
        uint valueUsed = getBuyPrice(amount) * lockType / 100;
        require((lockType == 100 || lockType == 80 || lockType == 50 || lockType == 30) && amount > 0, "Error lockType OR Error amount");
        require(msg.value >= valueUsed, "Insufficient balance");
        uint startId = _nextTokenId();
        
        fomoPlay(msg.sender, amount);
        
        _mint(msg.sender, amount);

        for(uint i = startId; i < amount + startId; i++){
            if(lockType == 80){
                unlockTime[i] = block.timestamp + 2592000; // 30 days
            }else if(lockType == 50){
                unlockTime[i] = block.timestamp + 4320000; // 50 days
            }else if(lockType == 30){
                unlockTime[i] = block.timestamp + 7776000; // 90 days
            }
        }

        if(endTime > block.timestamp){
            usrBalanceForShare[msg.sender] = balanceOf(msg.sender);
        }

        if(inviteAddress != msg.sender){
            usrBalance[inviteAddress] += valueUsed * 2 / 100;
            inviteTotal[inviteAddress] ++;

            usrBalance[_protocol] += valueUsed * 1 / 100;

            if(endTime > block.timestamp){
                liqPool += valueUsed * 87 / 100;
                fomoPool += valueUsed / 10;
            }else{
                liqPool += valueUsed * 97 / 100;
            }
            
            uint256 overPayAmount = msg.value - valueUsed;
            if (overPayAmount > 0){
                payable(msg.sender).sendValue(overPayAmount);
            }

            emit Buy(msg.sender, inviteAddress, amount, valueUsed);
        }else{
            if(endTime > block.timestamp){
                fomoPool += valueUsed * 12 / 100;
                liqPool += valueUsed * 87 / 100;
            }else{
                liqPool += valueUsed * 99 / 100;
            }

            usrBalance[_protocol] += valueUsed * 1 / 100;

            uint256 overPayAmount = msg.value - valueUsed;
            if (overPayAmount > 0){
                payable(msg.sender).sendValue(overPayAmount);
            }

            emit Buy(msg.sender, address(0), amount, valueUsed);
        }
    }

    function sell(uint256[] memory usrTokens)public nonReentrant{
        require(usrTokens.length <= 50, "Too many sales may lead to execution errors");
        uint sellAmount;
        for(uint i = 0; i < usrTokens.length; i++){
            if(ownerOf(usrTokens[i]) == msg.sender && unlockTime[usrTokens[i]] <= block.timestamp){
                _burn(usrTokens[i]);
                sellAmount ++;
            }
        }

        if(endTime > block.timestamp){
            usrBalanceForShare[msg.sender] = balanceOf(msg.sender);
        }

        uint sellPrice = _getSellPrice(sellAmount, totalSupply() + sellAmount);
        require(liqPool >= sellPrice, "Insufficient balance of pool, please wait a moment");
        liqPool -= sellPrice * 96 / 100;
        usrBalance[_protocol] += sellPrice * 1 / 100;
        payable(msg.sender).sendValue(sellPrice * 95 / 100);

        emit Sell(msg.sender, sellAmount, sellPrice);
    }
    
    function fomoPlay(address fomoPlayAddress, uint amount)internal{
        if(endTime > block.timestamp){
            for (uint i = _winners.length - 1; i > 0; i--) {
                _winners[i] = _winners[i - 1];
            }

            _winners[0] = fomoPlayAddress;

            endTime += 300 * amount;

            if(endTime > block.timestamp + 86400){
                endTime = block.timestamp + 86400;
            }

            emit FOMO(_winners[0], _winners[1], _winners[2], _winners[3], _winners[4], fomoPool, false);
        }else if(fomoPoolForEach == 0){
            usrBalance[_winners[0]] += fomoPool / 10;
            usrBalance[_winners[1]] += fomoPool / 10;
            usrBalance[_winners[2]] += fomoPool / 10;
            usrBalance[_winners[3]] += fomoPool / 10;
            usrBalance[_winners[4]] += fomoPool / 10;

            fomoPoolForEach = fomoPool * 5 / (10 * totalSupply());
            emit FOMO(_winners[0], _winners[1], _winners[2], _winners[3], _winners[4], fomoPool, true);

        }
    }

    function withdraw()public nonReentrant{
        require(usrCanWithdraw(msg.sender) > 0, "No balance");
        uint withdrawAmount = usrCanWithdraw(msg.sender);
        usrBalance[msg.sender] = 0;

        if(endTime <= block.timestamp && usrBalanceForShare[msg.sender] != 0){
            usrBalanceForShare[msg.sender] = 0;
        }

        payable(msg.sender).sendValue(withdrawAmount);
    }

    function getBuyPrice(uint amount) public view returns (uint) {
        uint sum_i = (amount * (amount - 1)) / 2;
        uint basePart = amount * _basePrice;

        uint stepPart = _step * (amount * totalSupply() + sum_i);

        return basePart + stepPart;
    }

    function getSellPrice(uint amount) public view returns (uint) {
        require(totalSupply() >= amount, "Not enough NFTs in supply to sell");

        uint sum_i = (amount * (amount - 1)) / 2;

        uint basePart = amount * _basePrice;

        uint stepPart = _step * (amount * (totalSupply() - 1) - sum_i);

        return basePart + stepPart;
    }

    function _getSellPrice(uint amount, uint total) private view returns (uint) {
        require(total >= amount, "Not enough NFTs in supply to sell");

        uint sum_i = (amount * (amount - 1)) / 2;

        uint basePart = amount * _basePrice;

        uint stepPart = _step * (amount * (total - 1) - sum_i);

        return basePart + stepPart;
    }
    
    function usrCanWithdraw(address usr)public view returns(uint){
        uint payAmount = usrBalance[usr];

        if(endTime <= block.timestamp && usrBalanceForShare[usr] != 0){
            payAmount += usrBalanceForShare[usr] * fomoPoolForEach;
        }

        return payAmount;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) 
    {
        uint256 x = tokenId % 500;
        return string(abi.encodePacked(baseURI, x.toString(),".json"));
    }

    function getWinners() public view returns (address[5] memory) {
        return _winners;
    }

}   