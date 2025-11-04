# Sparrow Finance - EVM Contracts

Multi-chain liquid staking protocol for Avalanche and Beam networks.

## Overview

Sparrow Finance enables users to stake native assets (AVAX, BEAM) and receive liquid staking tokens that appreciate in value as validator rewards accrue.

**Supported Networks:**
- Avalanche (spAVAX)
- Beam (spBEAM)

## Contracts

- `contracts/spAVAX_V1.sol` - Avalanche liquid staking
- `contracts/spBEAM/spBEAM_V1.sol` - Beam liquid staking

## Key Features

- Liquid staking with automatic value appreciation
- Unlock + claim window system (15-day unlock, 7-day claim)
- 8% protocol fee (5% DAO, 3% Dev)
- Emergency pause mechanism
- OpenZeppelin security components

## Installation

```bash
npm install
npx hardhat compile
npx hardhat test
```

## Deployment

See `MULTI_CHAIN_DEPLOYMENT.md` in archive folder for detailed deployment instructions.

## Security

- Built with OpenZeppelin contracts
- Reentrancy protection
- Access control (Ownable)
- Pausable for emergencies
- Comprehensive test coverage

## Documentation

Additional documentation available in `archive/` folder.

## License

MIT License

## Links

- Website: https://sparrowfinance.xyz
- Docs: https://docs.sparrowfinance.xyz
- Twitter: https://x.com/SPROFinance
- GitHub: https://github.com/Sparrow-Finance
