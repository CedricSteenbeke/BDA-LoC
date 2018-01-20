pragma solidity ^0.4.0;
import "Mortal.sol"
import "Owned.sol"

contract LetterOfCredit is Owned, Mortal {
    //State Machine, stages in the LoC
    enum Stages {
        LOCApplicationStart,
        ImporterBankApproval,
        ExporterBankApproval,
        Shipment,
        ReviewDocuments,
        ImporterReviewDocuments,
        Completed,
        Failed
    }
    Stages stages;

    address public importer;
    address public exporter;
    address public importerBank;
    address public exporterBank;

    uint256 private orderTotalPrice;

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
    event RequestApproval(address _forBank); //Request approval from _forBank
    event ReviewRequirements(address _forAddress); //request a review by _forAddress
    event ReviewDocuments(address _forAddress); //request a review of documents by _forAddress
    event ShipmentFinished(address _forAddress); //

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
    function addPurchaseOrder(bytes32 _purchaseOrderHash, uint256 _orderTotalPrice) onlyBy(importer) atStage(Stages.LOCApplicationStart) transitionNext external {
        orderTotalPrice = _orderTotalPrice;
        documentHashes[0] = _purchaseOrderHash;
        //change contract owner to importerBank so they can validate the documentHashes
        changeOwner(importerBank);
        RequestApproval(importerBank);
    }

    //approval functions is the same, only the 'owner' and stage is different...
    function approvePurchaseOrderImporterBank(bool _isApproved) onlyBy(importerBank) atStage(Stages.ImporterBankApproval) transitionNext external payable returns (bool) {
        if (!_isApproved) {
            // Bank did not approve, end
            stage = Stages.Failed;
            throw;
        }
        if (msg.value < orderTotalPrice) throw;
        
        etherAmount = msg.value;
        pendingWithdrawals[exporter] = orderTotalPrice;
        pendingWithdrawals[importerBank] = msg.value - orderTotalPrice;
        //change owner of the contract, so the exporterBank can validate the documentHashes
        changeOwner(exporterBank);
        RequestApproval(exporterBank);
        return true;
    }

    function approvePurchaseOrderExporterBank(bool _isApproved) onlyBy(exporterBank) atStage(Stages.ExporterBankApproval) transitionNext external {
        if (!_isApproved) {
            // Bank did not approve, end
            stage = Stages.Failed;
            kill(importerBank);
            throw;
        }
        //Change owner back to exporter so he can review the LoC (not mandatory)
        changeOwner(exporter);
        ReviewRequirements(exporter);
    }

    //the exporter has added all required documentsvia the addPhoto function to the contract
    function completeShipment(bytes32 _invoiceHash, bytes32 _exportDataHash) onlyBy(owner) atStage(Stages.Shipment) transitionNext external {
        if (_invoiceHash == "") {
            stage = Stages.Failed;
            kill(importerBank);
            throw;
        }

        if (_exportDataHash == "") {
            stage = Stages.Failed;
            kill(importerBank);
            throw;
        }
        documentHashes[1] = _invoiceHash;
        documentHashes[2] = _exportDataHash;
        changeOwner(exporterBank);
        ReviewDocuments(exporterBank);
    }

    function approveShipmentByExporterBank(bool _isApproved) onlyBy(exporterBank) atStage(Stages.ReviewDocuments) transitionNext external {
        if (!_isApproved) {
            // Bank did not approve, end
            stage = Stages.Failed;
            kill(importerBank);
            throw;
        }
        changeOwner(importerBank);
        ReviewDocuments(importerBank);
    }

    function approveShipmentByImporterBank(bool _isApproved) onlyBy(importerBank) atStage(Stages.ImporterReviewDocuments) transitionNext external{
        if (!_isApproved) {
            // Bank did not approve, return to shipment stage so the exporter
            // can add the corrected documents.
            // transitionNext will trasition to Shipment stage
            stage = Stages.ExporterBankApproval;
            changeOwner(importer);
            ReviewDocuments(importer);
        }else{
            //At this point the bank and exporter can withdraw their funds
            ShipmentFinished(importer);
        }
    }


    function addPhotoEvidence(uint32 photoNumber, bytes32 photoHash) onlyBy(exporter) atStage(Stages.Shipment) external {
        photoHashes[photoNumber] = photoHash;
    }

    function validateDocument(uint32 _id, bytes32 documentHash) onlyBy(owner) external returns (bool) {
        return documentHashes[_id] == documentHash;
    }

    function validatePhotoEvidence(uint32 _photoNumber, bytes32 _photoHash) onlyBy(owner) external returns (bool) {
        return documentHashes[_photoNumber] == _photoHash;
    }

    function checkOrderTotalPrice() external returns (uint256) {
        return orderTotalPrice;
    }

    function withdraw() atStage(Stages.Completed) external returns (bool) {
        uint amountToWithdraw = pendingWithdrawals[msg.sender];
        if(amountToWithdraw == 0) return false;
        // Remember to zero the pending refund before
        // sending to prevent re-entrancy attacks
        pendingWithdrawals[msg.sender] = 0;
        if (msg.sender.send(amountToWithdraw)) return true;
        pendingWithdrawals[msg.sender] = amountToWithdraw;
        return false;
    }

    function getStage() returns (uint) {
        return uint256(stages);
    }

    function nextStage() internal {
        stage = Stages(uint(stage) + 1);
    }

    // rejector
    function() public {throw;}
}
