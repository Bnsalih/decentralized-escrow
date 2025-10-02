# Decentralized Escrow Smart Contract

This repository contains a decentralized escrow smart contract designed to facilitate secure transactions between parties without the need for a trusted third party.

## Features

- **Create Escrow:** Initiate an escrow agreement between buyer and seller.
- **Fund Escrow:** Deposit funds into the escrow contract.
- **Release Funds:** Release funds to the seller upon successful completion of the agreement.
- **Event Emission:** Emits events for key actions to enable easy integration with front-end applications.

## Getting Started

### Prerequisites

- Node.js & npm
- Hardhat or Truffle (for deployment and testing)
- Solidity compiler

### Installation

Clone the repository:

```
git clone https://github.com/yourusername/decentralized-escrow.git
cd decentralized-escrow
```

Install dependencies:

```
npm install
```

### Deployment

Configure your network settings in `hardhat.config.js` or `truffle-config.js`, then deploy:

```
npx hardhat run scripts/deploy.js --network <network>
```

### Testing

Run unit tests:

```
npm test
```

## Usage

Interact with the contract using your preferred Ethereum wallet or through the provided scripts. Refer to the contract documentation for available functions and parameters.

## Contributing

Contributions are welcome! Please open issues or submit pull requests for improvements and bug fixes.
