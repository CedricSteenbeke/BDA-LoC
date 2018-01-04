pragma solidity ^0.4.0;

contract LetterOfCredit {
    
    address public buyer;
    address public seller;
    uint256 saleContractHash;
    bool validatedByBuyerBank;
    bool validatedBySellerBank;
    
    function LetterOfCredit(address _seller, uint256 _saleContractHash) public {
        buyer = msg.sender;
        seller = _seller;
        saleContractHash = _saleContractHash;
    }
    /**
     * Restriction
     */
    modifier onlyBuyer {
        require(msg.sender != buyer);
        _;
    }
    
    modifier onlySeller {
        require(msg.sender != seller);
        _;
    }
    
    // withdrawel pattern == zorgen dat de seller zijn geld krijgt
    // TODO: betere naam voor deze functie
    function creditSeller() onlySeller {
        if(!seller.send(this.balance))
        throw;
    }
    
    // rejector
    function() { throw; }
}
