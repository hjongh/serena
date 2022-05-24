// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.7.0 <0.9.0;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

/**
 * @notice Serena is an Ethereum-native decentralized store-of-value designed
 *     after HEX, with better game theory, optimal token distribution,
 *     significantly more gas-efficient code, and no centralized supply or
 *     special contract rules for founders.
 */
contract Serena is ERC20 {

    using Math for uint256;

    uint256 private constant LAUNCH_TIMESTAMP = 1647602549;
    uint256 private constant MINT_PHASE_END_TIMESTAMP = LAUNCH_TIMESTAMP + 100 days;

    uint256 private constant MINT_RATE_REDUCTION_1_DAY = 21;
    uint256 private constant MINT_RATE_REDUCTION_2_DAY = 41;
    uint256 private constant MINT_RATE_REDUCTION_3_DAY = 61;
    uint256 private constant MINT_RATE_REDUCTION_4_DAY = 81;

    uint256 private constant daysForHalvening = 90;
    uint256 private constant HIGH_INFLATION_PHASE_START_DAY = 101;
    uint256 private constant HALVENING_1_DAY = HIGH_INFLATION_PHASE_START_DAY + daysForHalvening;
    uint256 private constant HALVENING_2_DAY = HALVENING_1_DAY + daysForHalvening;
    uint256 private constant HALVENING_3_DAY = HALVENING_2_DAY + daysForHalvening;
    uint256 private constant HALVENING_4_DAY = HALVENING_3_DAY + daysForHalvening;
    uint256 private constant HALVENING_5_DAY = HALVENING_4_DAY + daysForHalvening;

    address private constant ETH_MAINNET_USDC_ADDR = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant ETH_MAINNET_HEX_ADDR = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39;
    address private constant ETH_MAINNET_USDT_ADDR = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant KOVAN_USDC_ADDR = 0xb7a4F3E9097C08dA09517b5aB877F7a917224ede;
    address private constant KOVAN_USDT_ADDR = 0x07de306FF27a2B630B1141956844eB1552B956B5;

    address private constant CHAINLINK_ETH_USD_ADDR = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private constant KOVAN_CHAINLINK_ETH_USD_ADDR = 0x9326BFA02ADD2366b30bacB125260Af641031331;
    uint256 private constant CHAINLINK_ETH_DECIMAL_PLACES = 8;

    address private constant ETH_MAINNET_UNIV3_HEX_USDC_POOL_ADDR = 0xe05e653453F733786F2DABae0ffa1e96cFcc4b25;
    uint256 private constant NUM_EXTRA_BITS_PRECISION_HEX_USDC_SQRTPRICEX96 = 10;

    uint256 private constant TEST_HEX_USDC_SQRTPRICEX96 = 2715057749264842560720630196;

    // These numbers include the decimal places for each coin
    uint256 private constant LAUNCH_RATIO_SERENA_PER_USD = 1e24;
    uint256 private constant LAUNCH_RATIO_SERENA_PER_STABLE = LAUNCH_RATIO_SERENA_PER_USD / 1e6;
    uint256 private constant LAUNCH_RATIO_SERENA_PER_ETHER = LAUNCH_RATIO_SERENA_PER_USD / 1e18;

    uint256 private constant MINT_RATE_EXTRA_PRECISION = 1e3;
    uint256 private constant MINT_RATE_REDUCED_1 = 975;
    uint256 private constant MINT_RATE_REDUCED_2 = 950;
    uint256 private constant MINT_RATE_REDUCED_3 = 925;
    uint256 private constant MINT_RATE_REDUCED_4 = 900;

    // Mint phase referral bonus is 5%
    uint256 private constant MINT_REFERRAL_DIVISOR = 20;

    // Discourage flash loan attack. Maximum allowed HEX price of 50c.
    uint256 private constant MAX_LAUNCH_RATIO_SERENA_PER_HEX =
        LAUNCH_RATIO_SERENA_PER_USD / 2 / 1e8;

    address private constant SERENA_GROWTH_ADDR = 0x5Cfc021e42d0cFD7Ea2639eaE693910bA900Ef67;
    address private constant MINT_SACRIFICE_ADDR = 0xF8656b3f2c0D0bEd70d7276fdEC6BD082263437A;
    address private constant SERENA_FOUNDER_ADDR = 0x5dCb24D66963966C271DC7D4e77Bd97bD4c108E3;

    uint256 private constant FOUNDER_SUPPLY_DIVISOR = 10;

    /**
     * We want indivisible rather than fractional shares because:
     * 1. Shares are generally indivisible in the real world
     * 2. Solidity doesn't have built-in floating point numbers.
     * However, we also want precision. Starting at an arbitrary conversion
     * rate of 1 share per 1 Serena (1e18 - recall Serena has 18 decimals), we
     * add 8 decimal places of precision to the share supply by making shares
     * 1e8 times cheaper. The result is that shares have a very large supply.
     * For ease of use, we attach numeric prefixes to shares in the same way
     * HEX does (ex: 1 T-share = 1 trillion shares). Using this naming
     * convention, the initial share price is 10,000 Serena per T-share.
     */
    uint256 private constant INITIAL_SHARE_PRICE = 1e10;

    /**
     * This ensures even a 1 day timelock's share bonus is represented in the
     * share calculations.
     */
    uint256 private constant SHARE_BONUS_DECIMAL_PLACES = 1e6;

    uint256 private constant MIN_DAYS_TIMELOCK = 1;
    uint256 private constant MAX_DAYS_TIMELOCK = 3650;

    /**
     * Serena uses a ratio that ranges from 0 to 1 to calculate the early
     * penalty, but Solidity doesn't have floating point, so we need this.
     */
    uint256 private constant EARLY_PENALTY_PRECISION = 1e3;

    uint256 private constant DAYS_TILL_LATE_PENALTY = 365;

    /**
     * The annual interest rate is 1.8%.
     * 1.000049 ^ 365 ~= 1.018
     * 1 / 0.000049 ~= 20408
     */
    uint256 private constant DAILY_INTEREST_DIVISOR = 20408;

    /**
     * 1 / (0.576 / 365) ~= 634
     */
    uint256 private constant HIGH_INFLATION_INTEREST_DIVISOR_1 = 634;

    /**
     * 1 / (0.288 / 365) ~= 1267
     */
    uint256 private constant HIGH_INFLATION_INTEREST_DIVISOR_2 = 1267;

    /**
     * 1 / (0.144 / 365) ~= 2535
     */
    uint256 private constant HIGH_INFLATION_INTEREST_DIVISOR_3 = 2535;

    /**
     * 1 / (0.072 / 365) ~= 5069
     */
    uint256 private constant HIGH_INFLATION_INTEREST_DIVISOR_4 = 5069;

    /**
     * 1 / (0.036 / 365) ~= 10139
     */
    uint256 private constant HIGH_INFLATION_INTEREST_DIVISOR_5 = 10139;

    struct GlobalsStore {
        uint256 totalShareSupply;
        uint256 sharePrice;
        uint128 numCompletedDays;
        uint128 latestTimelockId;
    }

    struct GlobalsCache {
        uint256 _totalShareSupply;
        uint256 _sharePrice;
        uint256 _numCompletedDays;
        uint256 _latestTimelockId;
    }

    struct TimelockStore {
        uint256 serenaAmount;
        uint256 numShares;
        uint128 id;
        uint112 dayCreated;
        uint16 daysTimelocked;
    }

    struct TimelockCache {
        uint256 _serenaAmount;
        uint256 _numShares;
        uint256 _id;
        uint256 _dayCreated;
        uint256 _daysTimelocked;
    }

    GlobalsStore public globals;
    mapping(address => TimelockStore[]) public timelockLists;
    // Maps days to prefix sums for daily interest per share.
    mapping(uint256 => uint256) public interestPerSharePrefixSums;
    uint256 public undistributedPenalties;

    event MintBySacrificingEther(
        address indexed sacrificer,
        uint256 amountOfEther
    );

    event MintBySacrificingUSDC(
        address indexed sacrificer,
        uint256 amountOfUSDC
    );

    event MintBySacrificingHEX(
        address indexed sacrificer,
        uint256 amountOfHEX
    );

    event MintBySacrificingUSDT(
        address indexed sacrificer,
        uint256 amountOfUSDT
    );

    event StartTimelock(
        address indexed timelockOwner,
        uint256 amountOfSerena,
        uint16 daysTimelocked
    );

    event EndTimelock(
        address indexed timelockOwner,
        uint32 timelockIndex,
        uint128 timelockId,
        uint256 originallyTimelockedSerena
    );

    event EndTimelockAfterDeadline(
        address indexed timelockOwner,
        uint32 timelockIndex,
        uint128 timelockId,
        uint256 originallyTimelockedSerena
    );

    modifier isAfterLaunch {
        require(
            block.timestamp >= LAUNCH_TIMESTAMP,
            "SRNA: Project has not launched yet."
        );
        _;
    }

    modifier isBeforeEndOfMintPhase {
        require(
            block.timestamp < MINT_PHASE_END_TIMESTAMP,
            "SRNA: Mint phase is over."
        );
        _;
    }
    
    constructor() ERC20("Serena", "SRNA") {
        globals.sharePrice = INITIAL_SHARE_PRICE;

        // TEST TODO
        LAUNCH_TIMESTAMP = block.timestamp;
        MINT_PHASE_END_TIMESTAMP = LAUNCH_TIMESTAMP + 45 seconds;
    }

    // ====================== EXTERNAL WRITE FUNCTIONS ======================

    /**
     * @notice Mint Serena during the launch phase by sacrificing Ether.
     * @param referrer Address of referrer.
     */
    function mintDuringLaunchBySacrificingEther(
        address referrer
    )
        external
        payable
        isAfterLaunch
        isBeforeEndOfMintPhase
    {
        uint256 serenaToMint = _calculateSerenaToMintForEther(msg.value);
        serenaToMint = _calculateSerenaToMintWithMintRate(serenaToMint);

        uint256 serenaGrowthFunds = msg.value / 4;
        payable(SERENA_GROWTH_ADDR).transfer(serenaGrowthFunds);
        payable(MINT_SACRIFICE_ADDR).transfer(msg.value - serenaGrowthFunds);

        uint256 referrerBonus;
        if (referrer != msg.sender) {
            referrerBonus = serenaToMint / MINT_REFERRAL_DIVISOR;
            _mint(referrer, referrerBonus);
            serenaToMint += referrerBonus;
        }
        _mint(msg.sender, serenaToMint);
        _mint(SERENA_FOUNDER_ADDR, (serenaToMint + referrerBonus) / FOUNDER_SUPPLY_DIVISOR);

        emit MintBySacrificingEther(msg.sender, msg.value);
    }

    /**
     * @notice Mint Serena during the launch phase by sacrificing USDC.
     * @param amountOfUSDC Amount of USDC to sacrifice to mint Serena.
     * @param referrer Address of referrer.
     */
    function mintDuringLaunchBySacrificingUSDC(
        uint256 amountOfUSDC,
        address referrer
    )
        external
        isAfterLaunch
        isBeforeEndOfMintPhase
    {
        uint256 serenaToMint = amountOfUSDC * LAUNCH_RATIO_SERENA_PER_STABLE;
        serenaToMint = _calculateSerenaToMintWithMintRate(serenaToMint);

        uint256 serenaGrowthFunds = amountOfUSDC / 4;
        IERC20(KOVAN_USDC_ADDR).transferFrom(msg.sender, SERENA_GROWTH_ADDR, serenaGrowthFunds);
        IERC20(KOVAN_USDC_ADDR).transferFrom(msg.sender, MINT_SACRIFICE_ADDR, amountOfUSDC - serenaGrowthFunds);
        
        uint256 referrerBonus;
        if (referrer != msg.sender) {
            referrerBonus = serenaToMint / MINT_REFERRAL_DIVISOR;
            _mint(referrer, referrerBonus);
            serenaToMint += referrerBonus;
        }
        _mint(msg.sender, serenaToMint);
        _mint(SERENA_FOUNDER_ADDR, (serenaToMint + referrerBonus) / FOUNDER_SUPPLY_DIVISOR);

        emit MintBySacrificingUSDC(msg.sender, amountOfUSDC);
    }

    /**
     * @notice Mint Serena during the launch phase by sacrificing HEX.
     * @param amountOfHEX Amount of HEX to sacrifice to mint Serena.
     * @param referrer Address of referrer.
     */
    function mintDuringLaunchBySacrificingHEX(
        uint256 amountOfHEX,
        address referrer
    )
        external
        isAfterLaunch
        isBeforeEndOfMintPhase
    {
        uint256 serenaToMint = _calculateSerenaToMintForHEX(amountOfHEX);
        serenaToMint = _calculateSerenaToMintWithMintRate(serenaToMint);

        uint256 serenaGrowthFunds = amountOfHEX / 4;
        IERC20(ETH_MAINNET_HEX_ADDR).transferFrom(msg.sender, SERENA_GROWTH_ADDR, serenaGrowthFunds);
        IERC20(ETH_MAINNET_HEX_ADDR).transferFrom(msg.sender, MINT_SACRIFICE_ADDR, amountOfHEX - serenaGrowthFunds);

        uint256 referrerBonus;
        if (referrer != msg.sender) {
            referrerBonus = serenaToMint / MINT_REFERRAL_DIVISOR;
            _mint(referrer, referrerBonus);
            serenaToMint += referrerBonus;
        }
        _mint(msg.sender, serenaToMint);
        _mint(SERENA_FOUNDER_ADDR, (serenaToMint + referrerBonus) / FOUNDER_SUPPLY_DIVISOR);

        emit MintBySacrificingHEX(msg.sender, amountOfHEX);
    }

    /**
     * @notice Mint Serena during the launch phase by sacrificing USDT.
     * @param amountOfUSDT Amount of USDT to sacrifice to mint Serena.
     * @param referrer Address of referrer.
     */
    function mintDuringLaunchBySacrificingUSDT(
        uint256 amountOfUSDT,
        address referrer
    )
        external
        isAfterLaunch
        isBeforeEndOfMintPhase
    {
        uint256 serenaToMint = amountOfUSDT * LAUNCH_RATIO_SERENA_PER_STABLE;
        serenaToMint = _calculateSerenaToMintWithMintRate(serenaToMint);

        uint256 serenaGrowthFunds = amountOfUSDT / 4;
        IERC20(ETH_MAINNET_USDT_ADDR).transferFrom(msg.sender, SERENA_GROWTH_ADDR, serenaGrowthFunds);
        IERC20(ETH_MAINNET_USDT_ADDR).transferFrom(msg.sender, MINT_SACRIFICE_ADDR, amountOfUSDT - serenaGrowthFunds);

        uint256 referrerBonus;
        if (referrer != msg.sender) {
            referrerBonus = serenaToMint / MINT_REFERRAL_DIVISOR;
            _mint(referrer, referrerBonus);
            serenaToMint += referrerBonus;
        }
        _mint(msg.sender, serenaToMint);
        _mint(SERENA_FOUNDER_ADDR, (serenaToMint + referrerBonus) / FOUNDER_SUPPLY_DIVISOR);

        emit MintBySacrificingUSDT(msg.sender, amountOfUSDT);
    }

    /**
     * @notice Start a timelock.
     * @dev Timelocked Serena are transferred to the contract address for the
     *     duration of the timelock, and transferred back to the address that
     *     made the timelock when the timelock is ended.
     * @param amountOfSerena The amount of Serena to timelock.
     * @param daysToTimelock The number of days to timelock the Serena for.
     */
    function startTimelock(uint256 amountOfSerena, uint256 daysToTimelock)
        external
        isAfterLaunch
    {
        require(
            daysToTimelock >= MIN_DAYS_TIMELOCK && daysToTimelock <=
                MAX_DAYS_TIMELOCK,
            "SRNA: Not in the valid range of days to timelock."
        );

        GlobalsCache memory globalsCache;
        _loadGlobalsIntoCache(globalsCache);

        uint256 currentDay = _currentDay();
        _updateContractStateForNewlyCompletedDaysIfNecessary(
            currentDay,
            globalsCache
        );

        _updateContractStateForNewTimelock(
            amountOfSerena,
            daysToTimelock,
            currentDay,
            globalsCache
        );

        _transfer(msg.sender, address(this), amountOfSerena);

        emit StartTimelock(
            msg.sender,
            amountOfSerena,
            uint16(daysToTimelock)
        );
    }

    /**
     * @notice End a timelock.
     * @dev This function includes ending timelocks early and late
     * @param timelockIndex The index of the timelock in the user's list of
     *     timelocks which is stored internally in the contract. These indexes
     *     are not fixed and can change for any given timelock.
     * @param timelockId The (globally unique) id of the timelock.
     */
    function endTimelock(uint256 timelockIndex, uint256 timelockId)
        external
        isAfterLaunch
    {
        TimelockStore[] storage timelockList = timelockLists[msg.sender];
        uint256 timelockListLength = timelockList.length;
        require(
            timelockIndex < timelockListLength,
            "SRNA: No timelock exists at the given index for that address."
        );
        TimelockStore storage timelockStore = timelockList[timelockIndex];
        TimelockCache memory timelockCache;
        _loadTimelockIntoCache(timelockStore, timelockCache);
        require(
            timelockCache._id == timelockId,
            "SRNA: The specified timelock doesn't have the given id."
        );

        GlobalsCache memory globalsCache;
        _loadGlobalsIntoCache(globalsCache);

        uint256 currentDay = _currentDay();
        uint256 latestInterestPrefixSum =
            _updateContractStateForNewlyCompletedDaysIfNecessary(
                currentDay,
                globalsCache
            );

        uint256 timelockEndDay = timelockCache._dayCreated +
            timelockCache._daysTimelocked;
        uint256 totalTimelockPayout = _updateContractStateForEndTimelock(
            timelockIndex,
            timelockList,
            timelockListLength,
            timelockCache,
            globalsCache,
            currentDay,
            timelockEndDay,
            latestInterestPrefixSum
        );

        _transfer(address(this), msg.sender, totalTimelockPayout);

        emit EndTimelock(
            msg.sender,
            uint32(timelockIndex),
            uint128(timelockId),
            timelockCache._serenaAmount
        );
    }

    /**
     * @notice End a timelock after the late deadline. This function can be
     *     called by anyone for any timelock that has passed its late
     *     deadline.
     * @param timelockOwner The address of the owner of the timelock.
     * @param timelockIndex The index of the timelock in the user's list of
     *     timelocks which is stored internally in the contract. These indexes
     *     are not fixed and can change for any given timelock.
     * @param timelockId The (globally unique) id of the timelock.
     */
    function endTimelockAfterDeadline(
        address timelockOwner,
        uint256 timelockIndex,
        uint256 timelockId
    )
        external
        isAfterLaunch
    {
        TimelockStore[] storage timelockList = timelockLists[timelockOwner];
        uint256 timelockListLength = timelockList.length;
        require(
            timelockIndex < timelockListLength,
            "SRNA: No timelock exists at the given index for that address."
        );
        TimelockStore storage timelockStore = timelockList[timelockIndex];
        TimelockCache memory timelockCache;
        _loadTimelockIntoCache(timelockStore, timelockCache);
        require(
            timelockCache._id == timelockId,
            "SRNA: The specified timelock doesn't have the given id."
        );
        uint256 currentDay = _currentDay();
        uint256 timelockEndDay = timelockCache._dayCreated +
            timelockCache._daysTimelocked;
        require(
            currentDay >= timelockEndDay + DAYS_TILL_LATE_PENALTY,
            "SRNA: The specified timelock hasn't reached the end deadline yet."
        );

        GlobalsCache memory globalsCache;
        _loadGlobalsIntoCache(globalsCache);

        uint256 latestInterestPrefixSum =
            _updateContractStateForNewlyCompletedDaysIfNecessary(
                currentDay,
                globalsCache
            );

        uint256 totalTimelockPayout = _updateContractStateForEndTimelock(
            timelockIndex,
            timelockList,
            timelockListLength,
            timelockCache,
            globalsCache,
            currentDay,
            timelockEndDay,
            latestInterestPrefixSum
        );

        _transfer(address(this), timelockOwner, totalTimelockPayout);

        emit EndTimelockAfterDeadline(
            timelockOwner,
            uint32(timelockIndex),
            uint128(timelockId),
            timelockCache._serenaAmount
        );
    }

    /**
     * @notice Update the contract state up to the given day (exclusive).
     * @dev This function exists so that the gas cost for transactions after
     *     long stretches of time without updating the contract can be broken
     *     up. The day indexing is from the Serena contract and can be
     *     retrieved by calling getCurrentDay().
     * @param day The day (exclusive) to update the contract state to.
     */
    function updateContractStateUpToDay(
        uint256 day
    )
        external
        isAfterLaunch
    {
        GlobalsCache memory globalsCache;
        globalsCache._numCompletedDays = globals.numCompletedDays;
        require(day > globalsCache._numCompletedDays + 1);

        globalsCache._totalShareSupply = globals.totalShareSupply;
        _updateContractStateForNewlyCompletedDaysIfNecessary(
            _currentDay().min(day),
            globalsCache
        );
    }

    // ======================= EXTERNAL READ FUNCTIONS =======================

    /**
     * @notice Calculates the amount of shares for a potential timelock.
     * @dev Included for use in the front-end.
     * @param amountOfSerena The amount of Serena that would be timelocked.
     * @param daysToTimelock The number of days that the timelock would be
     *     made for.
     */
    function calculateTimelockShares(
        uint256 amountOfSerena,
        uint256 daysToTimelock
    )
        external
        view
        returns (uint256)
    {
        return _calculateTimelockShares(
            amountOfSerena,
            daysToTimelock,
            globals.sharePrice
        );
    }

    /**
     * @notice Returns the interest a timelock has accrued so far.
     * @dev Included for use in the front-end. This function can return an
     *     answer that isn't up-to-date with the real world if the Serena
     *     contract hasn't had its daily interest prefix sums updated to the
     *     current day yet.
     * @param timelockOwner The address of the owner of the timelock.
     * @param timelockIndex The index of the timelock in the owner's list of
     *     timelocks.
     * @param timelockId The (globally unique) id of the timelock.
     */
    function calculateTimelockInterest(
        address timelockOwner,
        uint256 timelockIndex,
        uint256 timelockId
    )
        external
        view
        returns (uint256)
    {
        TimelockStore[] storage timelockList = timelockLists[timelockOwner];
        require(
            timelockIndex < timelockList.length,
            "SRNA: No timelock exists at the given index for that address."
        );
        TimelockStore storage timelockStore = timelockList[timelockIndex];
        require(
            timelockStore.id == timelockId,
            "SRNA: The specified timelock doesn't have the given id."
        );

        uint256 timelockDayCreated = timelockStore.dayCreated;
        uint256 currentDay = _currentDay();
        uint256 timelockInterest = 0;
        if (currentDay > timelockDayCreated) {
            uint256 startInterestPrefixSum =
                interestPerSharePrefixSums[timelockDayCreated - 1];
            uint256 timelockEndDay = timelockDayCreated +
                timelockStore.daysTimelocked;
            uint256 lastDayOfInterest = (currentDay - 1)
                .min(timelockEndDay - 1);
            uint256 endInterestPrefixSum =
                interestPerSharePrefixSums[lastDayOfInterest];
            uint256 timelockNetInterestPerShare = endInterestPrefixSum -
                startInterestPrefixSum;
            timelockInterest = timelockStore.numShares *
                timelockNetInterestPerShare;
        }

        return timelockInterest;
    }

    /**
     * @notice Returns the current day of the Serena contract.
     */
    function getCurrentDay() external view returns (uint256) {
        return _currentDay();
    }

    // ====================== INTERNAL READ FUNCTIONS ======================

    /**
     * @dev 1-indexed
     */
    function _currentDay()
        private
        view
        returns (uint256)
    {
        return (block.timestamp - LAUNCH_TIMESTAMP) / 1 days + 1;
    }

    function _calculateSerenaToMintWithMintRate(
        uint256 amountOfSerena
    )
        private
        view
        returns (uint256)
    {
        uint256 currentDay = _currentDay();
        if (currentDay < MINT_RATE_REDUCTION_1_DAY) {
            return amountOfSerena;
        } else if (currentDay < MINT_RATE_REDUCTION_2_DAY) {
            return amountOfSerena * MINT_RATE_REDUCED_1 /
                MINT_RATE_EXTRA_PRECISION;
        } else if (currentDay < MINT_RATE_REDUCTION_3_DAY) {
            return amountOfSerena * MINT_RATE_REDUCED_2 /
                MINT_RATE_EXTRA_PRECISION;
        } else if (currentDay < MINT_RATE_REDUCTION_4_DAY) {
            return amountOfSerena * MINT_RATE_REDUCED_3 /
                MINT_RATE_EXTRA_PRECISION;
        } else {
            return amountOfSerena * MINT_RATE_REDUCED_4 /
                MINT_RATE_EXTRA_PRECISION;
        }
    }

    function _calculateSerenaToMintForEther(uint256 amountOfEther)
        private
        view
        returns (uint256)
    {
        uint256 etherPrice = _getEtherPriceFromOracle();
        uint256 serenaToMint = amountOfEther * etherPrice /
            (10 ** CHAINLINK_ETH_DECIMAL_PLACES) *
            LAUNCH_RATIO_SERENA_PER_ETHER;
        return serenaToMint;
    }

    function _getEtherPriceFromOracle()
        private
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed =
            AggregatorV3Interface(KOVAN_CHAINLINK_ETH_USD_ADDR);
        int256 price;
        (,price,,,) = priceFeed.latestRoundData();
        return uint256(price);
    }

    function _calculateSerenaToMintForHEX(uint256 amountOfHEX)
        private
        view
        returns (uint256)
    {
        uint256 sqrtPriceX96 = _getSqrtPriceX96FromUniswapV3Pool(ETH_MAINNET_UNIV3_HEX_USDC_POOL_ADDR);
        uint256 sqrtPriceX96ExtraBits = sqrtPriceX96 *
            (2 ** NUM_EXTRA_BITS_PRECISION_HEX_USDC_SQRTPRICEX96);
        uint256 ratioOfUSDCToHEXExtraBits =
            _convertSqrtPriceX96ToRatio(sqrtPriceX96ExtraBits);
        uint256 serenaToMintExtraBits = amountOfHEX *
            ratioOfUSDCToHEXExtraBits * LAUNCH_RATIO_SERENA_PER_STABLE;
        uint256 serenaToMint = serenaToMintExtraBits /
            (2 ** (2 * NUM_EXTRA_BITS_PRECISION_HEX_USDC_SQRTPRICEX96));
        uint256 maxSerenaToMint = amountOfHEX * MAX_LAUNCH_RATIO_SERENA_PER_HEX;
        return serenaToMint.min(maxSerenaToMint);
    }

    function _getSqrtPriceX96FromUniswapV3Pool(address poolAddress)
        private
        view
        returns (uint256)
    {
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        uint256 sqrtPriceX96;
        (sqrtPriceX96, , , , , ,) = pool.slot0();
        return sqrtPriceX96;
    }

    /**
     * @dev This ratio (from UniswapV3's price oracle) is token1/token0. It
     *     also doesn't contain information about the decimals of each coin.
     */
    function _convertSqrtPriceX96ToRatio(uint256 sqrtPriceX96)
        private
        pure
        returns (uint256)
    {
        return (sqrtPriceX96 / (2 ** 96)) ** 2;
    }

    function _loadGlobalsIntoCache(GlobalsCache memory globalsCache)
        private
        view
    {
        globalsCache._totalShareSupply = globals.totalShareSupply;
        globalsCache._sharePrice = globals.sharePrice;
        globalsCache._numCompletedDays = globals.numCompletedDays;
        globalsCache._latestTimelockId = globals.latestTimelockId;
    }

    function _loadTimelockIntoCache(
        TimelockStore storage timelockStore,
        TimelockCache memory timelockCache
    )
        private
        view
    {
        timelockCache._id = timelockStore.id;
        timelockCache._serenaAmount = timelockStore.serenaAmount;
        timelockCache._numShares = timelockStore.numShares;
        timelockCache._dayCreated = timelockStore.dayCreated;
        timelockCache._daysTimelocked = timelockStore.daysTimelocked;
    }

    function _calculateTimelockShares(
        uint256 amountOfSerena,
        uint256 daysToTimelock,
        uint256 sharePrice
    )
        private
        pure
        returns(uint256)
    {
        uint256 shareBonusMultipleWithExtraPrecision =
            SHARE_BONUS_DECIMAL_PLACES * (daysToTimelock ** 2) /
            ((MAX_DAYS_TIMELOCK / 10) ** 2);
        uint256 shareMultipleWithExtraPrecision = SHARE_BONUS_DECIMAL_PLACES +
            shareBonusMultipleWithExtraPrecision;
        uint256 totalSharesWithExtraPrecision = amountOfSerena *
            shareMultipleWithExtraPrecision / sharePrice;
        return totalSharesWithExtraPrecision / SHARE_BONUS_DECIMAL_PLACES;
    }

    function _calculateNewSharePrice(
        uint256 amountOfSerena,
        uint256 daysTimelocked,
        uint256 sharesToReduceTo
    )
        private
        pure
        returns(uint256)
    {
        uint256 shareBonusMultipleWithExtraPrecision =
            SHARE_BONUS_DECIMAL_PLACES * (daysTimelocked ** 2) /
            ((MAX_DAYS_TIMELOCK / 10) ** 2);
        uint256 shareMultipleWithExtraPrecision = SHARE_BONUS_DECIMAL_PLACES +
            shareBonusMultipleWithExtraPrecision;
        uint256 newSharePriceWithExtraPrecision = amountOfSerena *
            shareMultipleWithExtraPrecision / sharesToReduceTo;
        uint256 newSharePrice = newSharePriceWithExtraPrecision /
            SHARE_BONUS_DECIMAL_PLACES;
        bool isRemainder = (amountOfSerena * shareMultipleWithExtraPrecision)
            % (sharesToReduceTo * SHARE_BONUS_DECIMAL_PLACES) != 0;
        // Round the share price up rather than down, to ensure giving
        // slightly less rather than slightly more shares.
        return isRemainder ? newSharePrice + 1 : newSharePrice;
    }

    function _calculateTimelockInterestBeforePenalties(
        TimelockCache memory timelockCache,
        uint256 currentDay,
        uint256 latestInterestPrefixSum,
        uint256 timelockEndDay
    )
        private
        view
        returns (uint256)
    {
        uint256 startInterestPrefixSum =
            interestPerSharePrefixSums[timelockCache._dayCreated - 1];

        uint256 endInterestPrefixSum;
        // We can avoid a redundant read if we wrote the latest prefix sum
        // when updating the daily interest prefix sums.
        if (_canReuseLatestInterestPrefixSum(currentDay, timelockEndDay,
                latestInterestPrefixSum)) {
            endInterestPrefixSum = latestInterestPrefixSum;
        } else if (_isTimelockEndedEarly(currentDay, timelockEndDay)) {
            endInterestPrefixSum = interestPerSharePrefixSums[currentDay - 1];
        } else {
            endInterestPrefixSum =
                interestPerSharePrefixSums[timelockEndDay - 1];
        }

        return timelockCache._numShares *
            (endInterestPrefixSum - startInterestPrefixSum);
    }

    function _canReuseLatestInterestPrefixSum(
        uint256 currentDay,
        uint256 timelockEndDay,
        uint256 latestInterestPrefixSum
    )
        private
        pure
        returns (bool)
    {
        return timelockEndDay == currentDay && latestInterestPrefixSum != 0;
    }

    function _isTimelockEndedEarly(
        uint256 currentDay,
        uint256 timelockEndDay
    )
        private
        pure
        returns (bool)
    {
        return currentDay < timelockEndDay;
    }

    function _isTimelockPastDeadline(
        uint256 currentDay,
        uint256 timelockEndDay
    )
        private
        pure
        returns (bool)
    {
        return currentDay >= timelockEndDay + DAYS_TILL_LATE_PENALTY;
    }

    function _calculateTimelockPenalty(
        uint256 currentDay,
        uint256 timelockEndDay,
        TimelockCache memory timelockCache,
        uint256 interestAmount
    )
        private
        pure
        returns (uint256)
    {
        if (_isTimelockEndedEarly(currentDay, timelockEndDay)) {
            uint256 daysCompleted = currentDay - timelockCache._dayCreated;
            uint256 proportionCompleted = EARLY_PENALTY_PRECISION *
                daysCompleted / timelockCache._daysTimelocked;
            uint256 penaltyProportion =
                (EARLY_PENALTY_PRECISION - proportionCompleted) ** 2;
            uint256 penaltyOnPrincipal = timelockCache._serenaAmount *
                penaltyProportion / (EARLY_PENALTY_PRECISION ** 2);
            return penaltyOnPrincipal + interestAmount;
        } else if (_isTimelockPastDeadline(currentDay, timelockEndDay)) {
            return interestAmount;
        } else {
            return 0;
        }
    }

    function _getInterestRateDivisor(
        uint256 currentDay
    )
        private
        pure
        returns(uint256)
    {
        if (currentDay >= HALVENING_5_DAY || currentDay < HIGH_INFLATION_PHASE_START_DAY) {
            return DAILY_INTEREST_DIVISOR;
        } else if (currentDay < HALVENING_1_DAY) {
            return HIGH_INFLATION_INTEREST_DIVISOR_1;
        } else if (currentDay < HALVENING_2_DAY) {
            return HIGH_INFLATION_INTEREST_DIVISOR_2;
        } else if (currentDay < HALVENING_3_DAY) {
            return HIGH_INFLATION_INTEREST_DIVISOR_3;
        } else if (currentDay < HALVENING_4_DAY) {
            return HIGH_INFLATION_INTEREST_DIVISOR_4;
        } else {
            return HIGH_INFLATION_INTEREST_DIVISOR_5;
        }
    }

    // ====================== INTERNAL WRITE FUNCTIONS ======================

    /**
     * @dev This function returns the latest interest prefix sum if new days
     *     were updated (which requires a read from storage), 0 otherwise. The
     *     reason for the return value is so that the contract can use the
     *     return value to avoid doing an unnecessary read in endTimelock().
     */
    function _updateContractStateForNewlyCompletedDaysIfNecessary(
        uint256 currentDay,
        GlobalsCache memory globalsCache
    )
        private
        returns (uint256)
    {
        return currentDay > globalsCache._numCompletedDays + 1 ?
            _updateContractStateForNewlyCompletedDays(
                currentDay,
                globalsCache
            ) :
            0;
    }

    function _updateContractStateForNewlyCompletedDays(
        uint256 currentDay,
        GlobalsCache memory globalsCache
    )
        private
        returns (uint256)
    {
        uint256 numCompletedDays = globalsCache._numCompletedDays;
        uint256 latestInterestPrefixSum =
            interestPerSharePrefixSums[numCompletedDays];
        uint256 totalSupply = totalSupply();
        uint256 interestDivisor = _getInterestRateDivisor(currentDay);
        uint256 dailyInterest = totalSupply / interestDivisor;
        uint256 dailyInterestWithPenalties = dailyInterest +
            undistributedPenalties;
        uint256 dailyInterestPerShare =
            globalsCache._totalShareSupply > 0 ?
            dailyInterest / globalsCache._totalShareSupply :
            0;
        uint256 dailyInterestWithPenaltiesPerShare =
            globalsCache._totalShareSupply > 0 ?
            dailyInterestWithPenalties / globalsCache._totalShareSupply :
            0;

        // We add the penalties only to the first day we need to calculate
        // interest for.
        latestInterestPrefixSum += dailyInterestWithPenaltiesPerShare;
        interestPerSharePrefixSums[numCompletedDays + 1] =
            latestInterestPrefixSum;
        for (uint256 i = 2; numCompletedDays + i < currentDay; i++) {
            latestInterestPrefixSum += dailyInterestPerShare;
            interestPerSharePrefixSums[numCompletedDays + i] =
                latestInterestPrefixSum;
        }

        undistributedPenalties = 0;
        globals.numCompletedDays = uint128(currentDay - 1);

        return latestInterestPrefixSum;
    }

    function _updateContractStateForNewTimelock(
        uint256 amountOfSerena,
        uint256 daysToTimelock,
        uint256 currentDay,
        GlobalsCache memory globalsCache
    )
        private
    {
        uint256 totalShares = _calculateTimelockShares(
            amountOfSerena,
            daysToTimelock,
            globalsCache._sharePrice
        );

        timelockLists[msg.sender].push(
            TimelockStore(
                amountOfSerena,
                totalShares,
                uint128(++globalsCache._latestTimelockId),
                uint112(currentDay),
                uint16(daysToTimelock)
            )
        );

        globals.totalShareSupply = globalsCache._totalShareSupply +
            totalShares;
        globals.latestTimelockId = uint128(globalsCache._latestTimelockId);
    }

    function _updateContractStateForEndTimelock(
        uint256 timelockIndex,
        TimelockStore[] storage timelockList,
        uint256 timelockListLength,
        TimelockCache memory timelockCache,
        GlobalsCache memory globalsCache,
        uint256 currentDay,
        uint256 timelockEndDay,
        uint256 latestInterestPrefixSum
    )
        private
        returns (uint256)
    {
        _removeTimelockFromContractState(
            timelockIndex,
            timelockList,
            timelockListLength,
            timelockCache,
            globalsCache
        );

        uint256 interestAmount = _calculateTimelockInterestBeforePenalties(
            timelockCache,
            currentDay,
            latestInterestPrefixSum,
            timelockEndDay
        );
        _mint(address(this), interestAmount);

        uint256 penalty = _calculateTimelockPenalty(
            currentDay,
            timelockEndDay,
            timelockCache,
            interestAmount
        );
        undistributedPenalties += penalty;

        uint256 totalTimelockPayout = timelockCache._serenaAmount +
            interestAmount - penalty;
        _updateSharePriceIfNecessary(
            totalTimelockPayout,
            timelockCache,
            globalsCache
        );

        return totalTimelockPayout;
    }

    function _removeTimelockFromContractState(
        uint256 timelockIndex,
        TimelockStore[] storage timelockList,
        uint256 timelockListLength,
        TimelockCache memory timelockCache,
        GlobalsCache memory globalsCache
    )
        private
    {
        globals.totalShareSupply = globalsCache._totalShareSupply -
            timelockCache._numShares;
        _deleteTimelockStore(timelockIndex, timelockList, timelockListLength);
    }

    function _updateSharePriceIfNecessary(
        uint256 totalTimelockPayout,
        TimelockCache memory timelockCache,
        GlobalsCache memory globalsCache
    )
        private
    {
        uint256 numSharesWithCompoundedInterest = _calculateTimelockShares(
            totalTimelockPayout,
            timelockCache._daysTimelocked,
            globalsCache._sharePrice
        );
        if (numSharesWithCompoundedInterest > timelockCache._numShares) {
            globals.sharePrice = _calculateNewSharePrice(
                totalTimelockPayout,
                timelockCache._daysTimelocked,
                timelockCache._numShares
            );
        }
    }

    /**
     * @dev Since we want to maintain a contiguous array, but we also don't
     *     want to shift an entire chunk of the array over when deleting from
     *     the middle, if the Timelock we want to delete isn't at the end of
     *     the array, we swap it with the last Timelock in the array before
     *     deleting it.
     */
    function _deleteTimelockStore(
        uint256 timelockIndex,
        TimelockStore[] storage timelockList,
        uint256 timelockListLength
    )
        private
    {
        if (timelockIndex != timelockListLength - 1)
            timelockList[timelockIndex] = timelockList[timelockListLength - 1];
        delete timelockList[timelockListLength - 1];
        timelockList.pop();
    }
}