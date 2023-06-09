# Cloud Computing and Services

This repository provides a Bash script to automate the setup of a MySQL master-slave replication system using Docker and Docker Compose. 
The script generates a Docker Compose file to run a MySQL master server, an initializer container, a populate container, and multiple MySQL slave servers, 
all within their own Docker network. The initializer container sets up replication users and links the slave servers to the master, while the populate 
container creates a sample database and table in the master server and populates it with sample data.

## Prerequisites
To use the files in this repository, you will need the following:
- [Docker](https://docs.docker.com/engine/install/ubuntu/)
- [Docker Compose](https://docs.docker.com/compose/install/)
- [Bash](https://www.gnu.org/software/bash/)

## Getting Started
To get started with this project, follow these steps:
1. Clone this repository to your local machine.
  ```
  git clone https://github.com/achilleaspappas/Cloud-Computing-and-Services.git
  ```
2. Unzip and move into the repository directory.
  ```
  cd Cloud-Computing-and-Services
  ```
3. Run the bash script with the desired number of replicas.
  ```
  ./start.sh <number-of-replicas>
  ```
  This will generate the necessary configuration files and Docker Compose file. After that, Docker Compose will launch the containers.

To check the status of the containers, use:
  ```
  docker-compose ps
  ```
  
## Contents
This repository contains the following files:
1. start.sh
2. stop.sh

## How It Works
This setup uses Docker to run the MySQL master and slave servers, as well as the initializer and populate containers, within isolated environments. Docker Compose is used to manage and coordinate these containers.

- MySQL master: This is the main MySQL server where all changes are made. It is set up to log all changes, which the slave servers will replicate.

- Initializer container: This container waits for the master server to start, then sets up the necessary replication users and links the slave servers to the master.

- Populate container: This container waits for the initializer to finish its tasks, then creates a sample database and table in the master server and populates it with sample data.

- MySQL slave servers: These servers are set up to replicate changes from the master server. This is done by reading the master's logs and applying the changes.

## Note
Remember that the ports used by the MySQL servers are randomly chosen from the ephemeral port range (49152–65535). If you need to connect to one of the servers, you can find the port number in the .env file that is created by the script.

## Cleaning Up
To stop and remove all the containers, use:
  ```
  ./stop.sh
  ```
This will stop and remove all container. Also this will remove all the files created by the start.sh. But this will not remove the data stored in the MySQL servers. If you want to remove the data as well, you can delete the data/ directory.

## Contributing

This is a university project so you can not contribute.

## Authors

* **[University of West Attica]** - *Provided the exersice*
* **[Achilleas Pappas]** - *Made the app*

## License

This project is licensed by University of West Attica as is a part of a university course. Do not redistribute.

## Acknowledgments

Thank you to **University of West Attica** and my professors for providing the resources and knowledge to complete this project.



