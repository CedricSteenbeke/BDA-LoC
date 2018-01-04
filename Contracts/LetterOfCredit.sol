pragma solidity ^0.4.0;

contract Owned  {
  address owner;

  modifier onlyOwner() {
    if (msg.sender==owner) _;
  }

  function owned() {
    owner = msg.sender;
  }

  function changeOwner(address newOwner) onlyOwner {
    owner = newOwner;
  }

  function getOwner() constant returns (address){
    return owner;
  }
}

contract LetterOfCredit is Owned {
    //State Machine, stages in the LoC
    enum Stages {
        LOApplication,
        ImporterBankApproval,
        ExporterBankApproval,
        ExporterValidation,
        Shipment,
        ReviewDocuments,
        ImporterReviewDocuments,
        Completed,
        Failed
    }
    
   
    address public buyer;
    address public seller;
    address public buyerBank; //store the bank addresses
    address public sellerBank;
    
    uint256 saleContractHash;
    
    bool validatedByBuyerBank;
    bool validatedBySellerBank;
    
    mapping (uint256 => bytes32) documentHashes;
    mapping (uint256 => bytes32) photoHashes;
    
    // This is the current stage.
    Stages public stage = Stages.LOApplication;
    
    function LetterOfCredit(address _seller, uint256 _saleContractHash, address _buyerBank, address _sellerBank) public {
        owned();
        buyer = msg.sender;
        seller = _seller;
        buyerBank = _buyerBank;
        sellerBank = _sellerBank;
        saleContractHash = _saleContractHash;
    }
    
    
    /**
     * Events 
     */
    event ProofCreated(
        uint256 indexed id,
        bytes32 documentHash
    );
    event requestApproval(address _forBank); //Request approval from _forBank
    event reviewRequirements(address _forAddress); //request a review by _forAddress
    event reviewDocuments(address _forAddress); //request a review of documents by _forAddress
    
    /**
     * Restrictions
     */
    modifier onlyBy(address _account) {
        require(msg.sender == _account);
        _;
    }
    /*
    modifier onlyBuyer {
        require(msg.sender == buyer);
        _;
    }
    
    modifier onlySeller {
        require(msg.sender == seller);
        _;
    }
    */
    //NOT NEEDE FOR NOW BECAUSE OF STATE MACHINE
    modifier noHashExistsYet(uint256 id) {
        require(documentHashes[id] == "");
        _;
    }
    
    //Modifier to restrict access to function in certain stages
    modifier atStage(Stages _stage) {
        require(stage == _stage);
        _;
    }
    // This modifier goes to the next stage
    // after the function is done.
    modifier transitionNext() {
        _;
        nextStage();
    }

    
    //proof of existence
    function addPurchaseOrder(bytes32 _purchaseOrderHash) onlyBy(buyer) atStage(Stages.LOApplication) transitionNext external{
        documentHashes[1] = _purchaseOrderHash;
        //change contract owner to buyerBank so they can validate the documentHashes
        changeOwner(buyerBank);
        requestApproval(buyerBank);
    }
    
    //approval functions is the same, only the 'owner' and stage is different...
    function approvePurchaseOrder(bool isApproved) onlyBy(buyerBank) atStage(Stages.ImporterBankApproval) external{
        if(!isApproved){
            // Bank did not approve, end
            stage = Stages.Failed;
            throw;
        }
        //change owner of the contract, so the sellerBank can validate the documentHashes
        changeOwner(sellerBank);
        //move to next Stages
        //didn't use the modifier cause i'm not 100% sure it will work as intended.
        requestApproval(sellerBank);
        nextStage();
    }

    function approvePurchaseOrderSeller(bool isApproved) onlyBy(sellerBank) atStage(Stages.ExporterBankApproval) external{
        if(!isApproved){
            // Bank did not approve, end
            stage = Stages.Failed;
            throw;
        }
        //Change owner back to seller so he can review the LoC (not mandatory)
        changeOwner(seller);
        //move to next Stages and fire event
        reviewRequirements(seller);
        nextStage();
    }
    
    function approveShippment(bool isApproved) onlyBy(sellerBank) atStage(Stages.ReviewDocuments) external{
        if(!isApproved){
            // Bank did not approve, end
            stage = Stages.Failed;
            throw;
        }
        //Change owner back to seller so he can review the LoC (not mandatory)
        changeOwner(buyerBank);
        //move to next Stages and fire event
        ReviewDocuments(buyerBank);
        nextStage();
    }
    
    function approveShippmentByImporter(bool isApproved) onlyBy(buyerBank) atStage(Stages.ImporterReviewDocuments) external{
        if(!isApproved){
            // Bank did not approve, end
            stage = Stages.Failed;
            //REFUND THE MONEY?
            throw;
        }
        
        //THE end
        //PAY the seller NOW
    }
    
    
    function addPhotoEvidence(uint photoNumber, bytes32 photoHash) onlyBy(owner) atStage(Stages.Shipment) external {
        photoHashes[photoNumber] = photoHash;
    }
    //the seller has added all required documentsvia the addPhoto function to the contract
    function completeShipment(bytes32 _invoiceHash, bytes32 _exportDataHash) onlyBy(owner) atStage(Stages.Shipment) external {
        if(_invoiceHash == ""){
            stage = Stages.Failed;
            throw;
        }
        
        if(_exportDataHash == ""){
            stage = Stages.Failed;
            throw;
        }
        documentHashes[2] = _invoiceHash;
        documentHashes[3] = _exportDataHash;
        changeOwner(sellerBank);
        reviewDocuments(sellerBank);
        nextStage();
    }
    
    function validatePurchaseOrder(bytes32 documentHash) onlyBy(owner) external view returns (bool) {
        return documentHashes[1] == documentHash;
    }
    function validatePhotoEvidence(uint photoNumber, bytes32 photoHash) onlyBy(owner) external view returns (bool) {
        return documentHashes[photoNumber] == photoHash;
    }
    
    // withdrawel pattern == zorgen dat de seller zijn geld krijgt
    // TODO: betere naam voor deze functie
    function creditSeller() external onlyBy(seller) {
        if(!seller.send(this.balance))
        throw;
    }
    
    
    function nextStage() internal {
        stage = Stages(uint(stage) + 1);
    }
    
    // rejector
    function() public { throw; }
}
