pragma solidity ^0.4.0;


contract Owned {
    address owner;

    modifier onlyOwner() {
        if (msg.sender == owner) _;
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
    LOCApplicationStart,
    ImporterBankApproval,
    ExporterBankApproval,
    ExporterValidation,
    Shipment,
    ReviewDocuments,
    ImporterReviewDocuments,
    Completed,
    Failed
    }

    address public importer;

    address public exporter;

    address public importerBank; //store the bank addresses
    address public exporterBank;

    bytes32 saleContractHash;

    bool validatedByImporterBank;

    bool validatedByExporterBank;

    bool exporterHasWithdrawn;

    bool importerBankHasWithdrawn;

    uint256 private amount;

    uint256 public etherAmount;

    mapping (uint32 => bytes32) documentHashes;

    mapping (uint32 => bytes32) photoHashes;

    mapping (address => uint256) pendingWithdrawals;

    // This is the current stage.
    Stages public stage = Stages.LOCApplicationStart;

    function LetterOfCredit(address _exporter, address _importerBank, address _exporterBank) public {
        if (_exporter == 0) throw;
        if (_importerBank == 0) throw;
        if (_exporterBank == 0) throw;
        owned();
        importer = msg.sender;
        exporter = _exporter;
        importerBank = _importerBank;
        exporterBank = _exporterBank;
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
        if(msg.sender != _account) throw;
        _;
    }

    //Modifier to restrict access to function in certain stages
    modifier atStage(Stages _stage) {
        if(stage != _stage) throw; 
        _;
    }
    // This modifier goes to the next stage
    // after the function is done.
    modifier transitionNext() {
        _;
        nextStage();
    }


    //proof of existence
    function addPurchaseOrder(bytes32 _purchaseOrderHash, uint256 _amount) onlyBy(importer) atStage(Stages.LOCApplicationStart) transitionNext external {
        amount = _amount;
        documentHashes[0] = _purchaseOrderHash;
        //change contract owner to importerBank so they can validate the documentHashes
        changeOwner(importerBank);
        requestApproval(importerBank);
    }

    //approval functions is the same, only the 'owner' and stage is different...
    function approvePurchaseOrderImporterBank(bool _isApproved) onlyBy(importerBank) atStage(Stages.ImporterBankApproval) transitionNext external payable returns (bool) {
        if (!_isApproved) {
            // Bank did not approve, end
            stage = Stages.Failed;
            throw;
        }
        if (msg.value < amount) throw;

        etherAmount = msg.value;
        pendingWithdrawals[exporter] = amount;
        pendingWithdrawals[importerBank] = msg.value - amount;
        //change owner of the contract, so the exporterBank can validate the documentHashes
        changeOwner(exporterBank);
        requestApproval(exporterBank);
        return true;
    }

    function approvePurchaseOrderExporterBank(bool isApproved) onlyBy(exporterBank) atStage(Stages.ExporterBankApproval) transitionNext external {
        if (!isApproved) {
            // Bank did not approve, end
            stage = Stages.Failed;
            throw;
        }
        //Change owner back to exporter so he can review the LoC (not mandatory)
        changeOwner(exporter);
        reviewRequirements(exporter);
    }

    //the exporter has added all required documentsvia the addPhoto function to the contract
    function completeShipment(bytes32 _invoiceHash, bytes32 _exportDataHash) onlyBy(owner) atStage(Stages.Shipment) transitionNext external {
        if (_invoiceHash == "") {
            stage = Stages.Failed;
            throw;
        }

        if (_exportDataHash == "") {
            stage = Stages.Failed;
            throw;
        }
        documentHashes[1] = _invoiceHash;
        documentHashes[2] = _exportDataHash;
        changeOwner(exporterBank);
        reviewDocuments(exporterBank);
    }

    function approveShipmentByExporterBank(bool _isApproved) onlyBy(exporterBank) atStage(Stages.ReviewDocuments) transitionNext external {
        if (!_isApproved) {
            // Bank did not approve, end
            stage = Stages.Failed;
            throw;
        }
        //Change owner back to exporter so he can review the LoC (not mandatory)
        changeOwner(importerBank);
        reviewDocuments(importerBank);
    }

    function approveShipmentByImporterBank(bool _isApproved) onlyBy(importerBank) atStage(Stages.ImporterReviewDocuments) transitionNext external {
        if (!_isApproved) {
            // Bank did not approve, end
            stage = Stages.Failed;
            //REFUND THE MONEY? --> mortal pattern?
            throw;
        }
        //THE end
        //PAY the exporter NOW
    }


    function addPhotoEvidence(uint32 photoNumber, bytes32 photoHash) onlyBy(owner) atStage(Stages.Shipment) external {
        photoHashes[photoNumber] = photoHash;
    }

    function validateDocument(uint32 _id, bytes32 documentHash) onlyBy(owner) external returns (bool) {
        return documentHashes[_id] == documentHash;
    }

    function validatePhotoEvidence(uint32 _photoNumber, bytes32 _photoHash) onlyBy(owner) external returns (bool) {
        return documentHashes[_photoNumber] == _photoHash;
    }

    function checkAmount() external returns (uint256) {
        return amount;
    }

    function withdraw() atStage(Stages.Completed) external returns (bool) {
        uint amountToWithdraw = pendingWithdrawals[msg.sender];
        // Remember to zero the pending refund before
        // sending to prevent re-entrancy attacks
        pendingWithdrawals[msg.sender] = 0;
        if (msg.sender.send(amountToWithdraw)) return true;
        pendingWithdrawals[msg.sender] = amountToWithdraw;
        return false;
    }

    function recoverFunds() onlyBy(importerBank) atStage(Stages.Failed) external returns (bool) {
        uint256 toRecover = etherAmount;
        etherAmount = 0;
        if(msg.sender.send(toRecover)) {
            return true;
        } else {
            etherAmount = toRecover;
            return false;
        }
    }

    function nextStage() internal {
        stage = Stages(uint(stage) + 1);
    }

    // rejector
    function() public {throw;}
}
