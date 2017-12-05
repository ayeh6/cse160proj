#include "../../includes/packet.h"
#include "../../includes/socket.h"
#include "../../includes/sendInfo.h"
#include "../../includes/channels.h"

module TransportP {
	provides interface Transport;

	uses interface List<socket_store_t> as Sockets;
	uses interface List<socket_store_t> as TempSockets;
	uses interface SimpleSend as Sender;
	uses interface List<LinkState> as Confirmed;
}

implementation {
   /**
    * Get a socket if there is one available.
    * @Side Client/Server
    * @return
    *    socket_t - return a socket file descriptor which is a number
    *    associated with a socket. If you are unable to allocated
    *    a socket then return a NULL socket_t.
    */
   command socket_t Transport.socket() {
	socket_t fd;
	uint8_t i;
	socket_store_t insert;
	if (call Sockets.size() < MAX_NUM_OF_SOCKETS) {
		insert.fd = call Sockets.size();
		insert.effectiveWindow = 128;
		insert.lastWritten = 0;
		insert.nextExpected = 0;
		insert.lastSent = 0;
		insert.lastRcvd = 0;
		insert.lastRead = 0;
		insert.src = TOS_NODE_ID;
		fd = call Sockets.size();
		for(i = 0; i < 128; i++)
		{
			insert.sendBuff[i] = '\0';
			insert.rcvdBuff[i] = '\0';
			insert.username[i] = '\0';
		}
		call Sockets.pushback(insert);
	}
	else {
		dbg(TRANSPORT_CHANNEL, "return NULL\n");
		return NULL;
	}
	return fd;
   }

   /**
    * Bind a socket with an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       you are binding.
    * @param
    *    socket_addr_t *addr: the source port and source address that
    *       you are biding to the socket, fd.
    * @Side Client/Server
    * @return error_t - SUCCESS if you were able to bind this socket, FAIL
    *       if you were unable to bind.
    */
   command error_t Transport.bind(socket_t fd, socket_addr_t *addr) {
	socket_store_t temp;
	socket_addr_t tempAddr;
	error_t success;
	bool found = FALSE;
	while (!call Sockets.isEmpty()) {
		temp = call Sockets.front();
		call Sockets.popfront();
		if (temp.fd == fd && !found) {
			tempAddr.port = addr->port;
			tempAddr.addr = addr->addr;
			temp.src = tempAddr.port;
			found = TRUE;
			//dbg(TRANSPORT_CHANNEL, "fd found, inserting addr of node %d port %d\n", tempAddr.addr, tempAddr.port);
			call TempSockets.pushfront(temp);
		}
		else {
			call TempSockets.pushfront(temp);
		}
	}
	while (!call TempSockets.isEmpty()) {
		call Sockets.pushfront(call TempSockets.front());
		call TempSockets.popfront();
	}
	if (found == TRUE)
		return success = SUCCESS;
	else
		return success = FAIL;
	
   }

   /**
    * Checks to see if there are socket connections to connect to and
    * if there is one, connect to it.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting an accept. remember, only do on listen. 
    * @side Server
    * @return socket_t - returns a new socket if the connection is
    *    accepted. this socket is a copy of the server socket but with
    *    a destination associated with the destination address and port.
    *    if not return a null socket.
    */
   command socket_t Transport.accept(socket_t fd) {
	socket_store_t temp;
	socket_t rt;
	bool found = FALSE;
	uint16_t at;
	uint16_t i = 0;
	for(i = 0; i < call Sockets.size(); i++)
	{
		temp = call Sockets.get(i);
		if(temp.fd == fd && found == FALSE && temp.state == LISTEN)
		{
			found = TRUE;
			at = i;
		}
	}
	if(found == TRUE)
	{
		//return socket_t with stuff
		temp = call Sockets.get(at);
		rt = temp.fd;
		return rt;
	}
	else
	{
		return NULL;
	}
			
   }

   /**
    * Write to the socket from a buffer. This data will eventually be
    * transmitted through your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a write.
    * @param
    *    uint8_t *buff: the buffer data that you are going to wrte from.
    * @param
    *    uint16_t bufflen: The amount of data that you are trying to
    *       submit.
    * @Side For your project, only client side. This could be both though.
    * @return uint16_t - return the amount of data you are able to write
    *    from the pass buffer. This may be shorter then bufflen
    */
            command uint16_t Transport.write(socket_t fd, uint8_t *buff, uint16_t bufflen, uint8_t flag) {
                socket_store_t temp, temp2;
		LinkState destination;
		pack write;
                uint16_t sockLen;
		char send[8];
		char sendBtemp[128];
                uint16_t i,j,at,buffcount,next;
                uint8_t buffsize, buffable, buffto, lastAckd, sending, msgListCount;
		uint8_t msgList[10];
                bool found = FALSE;
		write.src = TOS_NODE_ID;
		write.protocol = PROTOCOL_TCP;
		sockLen = call Sockets.size();
		msgListCount = 0;
		printf("we are at %d, flag %d\n", TOS_NODE_ID, flag);
		for(i = 0; i < 8; i++)
		{
			send[i] = '\0';
		}
		for(i = 0; i < 128; i++)
		{
			sendBtemp[i] = '\0';
		}
                for(i = 0; i < sockLen; i++)
                {
                        temp = call Sockets.get(i);
                        if(temp.fd == fd && found == FALSE)
                        {
                                at = i;
                                found = TRUE;
                        }
			msgList[i] = temp.dest.addr;
			msgListCount++;
                }
                if(found == FALSE)
                {
                        return 0;
                }
                else
                {
			temp = call Sockets.get(at);
			if(bufflen > 0)
			{
				temp.lastWritten = 0;
				temp.lastSent = 0;
				temp.lastAck = 0;
	                        //temp = call Sockets.get(at);
        	                if(bufflen > (128 - temp.lastWritten))
        	                {
        	                        buffable = 128 - temp.lastWritten;
	                        }
        	                else
                	        {
	                                buffable = bufflen;
        	                }
                	        buffcount = 0;
                        	buffto = temp.lastWritten + buffable;
				j = temp.lastSent;
				printf("writing\n");
        	                for(i = 0; i < buffto; i++)
                	        {
					printf("%c",buff[j]);
                                	temp.sendBuff[i] = buff[j];
					j++;
                	        }
				printf("\n");
				write.dest = temp.dest.addr;
				write.TTL = MAX_TTL;
				//printf("write.dest is %d\n", write.dest);
                	        temp.lastWritten = j;
				//printf("lastwritten is %d\n", temp.lastWritten);
				if(flag == 8)
				{
					temp.flag = 9;
				}
				else if(flag == 11)
				{
					//client message to server, send as 11
					for(i = 0; i < buffto; i++)
					{
						printf("%c",temp.sendBuff[i]);
					}
					temp.flag = 11;
				}
				else if(flag == 13)
				{
					//client whisper to server
					temp.flag = 13;
				}
				else
				{
					//regular data
					temp.flag = 0;
				}
				write.seq = i;
				lastAckd = temp.lastAck;
				j = 0;
				for(i = 0; i < 8; i++)
				{
					if(temp.lastSent < 128)
					{
						send[i] = buff[temp.lastSent];
						buffcount++;
					}
					else
					{
						j = i;
						break;
					}
					temp.lastSent++;
				}
				temp.lastSent = buffcount;
				for(i = 0; i < 128; i++)
				{
					sendBtemp[i] = temp.sendBuff[i];
				}
				for(i = 0; i < j; i++)
				{
					temp.sendBuff[i] = send[i];
				}
				memcpy(write.payload, &temp, (uint8_t) sizeof(temp));
				//write.payload = temp.sendBuff;
				for(i = 0; i < 128; i++)
				{
					temp.sendBuff[i] = sendBtemp[i];
				}
				//something something find username and send
				for(i = 0; i < call Confirmed.size(); i++)
				{
					destination = call Confirmed.get(i);
					printf("confirm: %d\n", destination.Dest);
					if(write.dest == destination.Dest)
					{
						next = destination.Next;
					}
				}
                	        while(!call Sockets.isEmpty())
                        	{
                                	temp2 = call Sockets.front();
	                                if(temp.fd == temp2.fd)
        	                        {
                	                        call TempSockets.pushfront(temp);
                        	        }
                                	else
	                                {
        	                                call TempSockets.pushfront(temp2);
                	                }
                        	        call Sockets.popfront();
	                        }
        	                while(!call TempSockets.isEmpty())
                	        {
                        	        call Sockets.pushfront(call TempSockets.front());
                                	call TempSockets.popfront();
	                        }
				//printf("sending tooooo: %d\n", next);
				call Sender.send(write, next);
                        	return buffcount;
			}
			else
			{
				if(flag == 11)
				{
					temp.flag = 11;
				}
				else if(flag == 13)
				{
					temp.flag = 13;
				}
				else
				{
					temp.flag = 0;
				}
				buffcount = 0;
				lastAckd = temp.lastSent;
				//printf("lastSent is %d\n", temp.lastSent);
				//printf("lastWritten is %d\n", temp.lastWritten);
				for(i = 0; i < 8; i++)
				{
					if(temp.lastSent < temp.lastWritten && temp.lastSent < 128)
					{
						send[i] = temp.sendBuff[temp.lastSent];
						sending = i+1;
						temp.lastSent++;
					}
					else
					{
						send[i] = '\0';
					}
				}
				/*if(sending < 8)
				{
					temp.lastAck = 0;
					temp.lastWritten = 0;
					temp.lastSent = 0;
				}*/
				//printf("printing sendarray\n");
				for(i = 0; i < 8; i++)
				{
				//	printf("%d\n", send[i]);
				}
				for(i = 0; i < 128; i++)
				{
					sendBtemp[i] = temp.sendBuff[i];
				}
				for(i = 0; i <= sending; i++)
				{
					temp.sendBuff[i] = send[i];
				}
				write.dest = temp.dest.addr;
				write.TTL = MAX_TTL;
				//printf("write.dest is %d\n", write.dest);
				//printf("lastwritten is %d\n", temp.lastWritten);
				write.seq = i;
				memcpy(write.payload, &temp, (uint8_t) sizeof(temp));
				for(i = 0; i < 128; i++)
				{
					temp.sendBuff[i] = sendBtemp[i];
				}
                                for (i = 0; i < call Confirmed.size(); i++)
                                {
                                        destination = call Confirmed.get(i);
                                        if (write.dest == destination.Dest)
                                        {
                                                //printf("found dest\n");
                                                next = destination.Next;
                                        }
                                }
                                while(!call Sockets.isEmpty())
                                {
                                        temp2 = call Sockets.front();
                                        if(temp.fd == temp2.fd)
                                        {
                                                call TempSockets.pushfront(temp);
                                        }
                                        else
                                        {
                                                call TempSockets.pushfront(temp2);
                                        }
                                        call Sockets.popfront();
                                }
                                while(!call TempSockets.isEmpty())
                                {
                                        call Sockets.pushfront(call TempSockets.front());
                                        call TempSockets.popfront();
                                }
                                //printf("sending tooooo: %d\n", next);
                                call Sender.send(write, next);
				return sending;
			}
                }
        }
   /**
    * This will pass the packet so you can handle it internally. 
    * @param
    *    pack *package: the TCP packet that you are handling.
    * @Side Client/Server 
    * @return uint16_t - return SUCCESS if you are able to handle this
    *    packet or FAIL if there are errors.
    */
	command error_t Transport.receive(pack* package) {
		error_t result;
		if(package->protocol != PROTOCOL_TCP)
		{
			result = FAIL;
			return result;
		}
		else
		{
			result = SUCCESS;
			return result;
		}
	}

   /**
    * Read from the socket and write this data to the buffer. This data
    * is obtained from your TCP implimentation.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that is attempting a read.
    * @param
    *    uint8_t *buff: the buffer that is being written.
    * @param
    *    uint16_t bufflen: the amount of data that can be written to the
    *       buffer.
    * @Side For your project, only server side. This could be both though.
    * @return uint16_t - return the amount of data you are able to read
    *    from the pass buffer. This may be shorter then bufflen
    */
    
        command uint16_t Transport.read(socket_t fd, uint8_t *buff, uint16_t bufflen, uint8_t flag) {
                socket_store_t temp, temp2;
		pack send;
		LinkState destination;
                uint16_t sockLen = call Sockets.size();
                uint16_t i, j, at, buffcount, next;
                uint8_t buffsize, buffable, buffto, msgListCount;
		uint8_t msgList[10];
		char sendUser[128];
		char sendMsg[128];
                bool found = FALSE;
		bool stringDone = FALSE;
		bool writing;
		msgListCount = 0;
		printf("we are at %d, flag %d\n", TOS_NODE_ID, flag);
		for(i = 0; i < 128; i++)
		{
			sendMsg[i] = '\0';
			sendUser[i] = '\0';
		}
                for(i = 0; i < sockLen; i++)
                {
                        temp = call Sockets.get(i);
                        if(temp.fd == fd && found == FALSE)
                        {
                                at = i;
                                found = TRUE;
                        }
			msgList[i] = temp.dest.addr;
			msgListCount++;
                }
                if(found == FALSE)
                {
                        return 0;
                }
                else
                {
                        //do buffer things
                        temp = call Sockets.get(at);
			if(flag == 9)
			{
				//user name store
				for(i = 0; i < bufflen; i++)
				{
					temp.username[i] = buff[i];
				}
				for(i = 0; i < bufflen; i++)
				{
					printf("%c", buff[i]);
				}
				printf("\n");
				printf("username is? %s\n",temp.username);
				while(!call Sockets.isEmpty())
	                        {
					printf("test1\n");
	                                temp2 = call Sockets.front();
	                                if(temp.fd != temp2.fd)
	                                {
	                                        call TempSockets.pushfront(call Sockets.front());
	                                }
        	                        else
                	                {
					        call TempSockets.pushfront(temp);
        	                        }
                	                call Sockets.popfront();
                        	}
                        	while(!call TempSockets.isEmpty())
                        	{
					printf("test2\n");
                                	call Sockets.pushfront(call TempSockets.front());
                                	call TempSockets.popfront();
                        	}
				return bufflen;
			}
			else
			{
				buffcount = 0;
 				//printf("effectivewindow is %d\n", temp.effectiveWindow);
				if(bufflen > temp.effectiveWindow)
				{
					buffable = temp.effectiveWindow;
                        	}
                        	else
                        	{
                        	        buffable = bufflen;
                        	}
                        	j = temp.nextExpected;
				for(i = 0; i < buffable; i++)
                        	{
					if(buff[i] == '\n')
					{
						stringDone = TRUE;
					}
                        	        temp.rcvdBuff[j] = buff[i];
                        	        j++;
                        	        buffcount++;
                        	        if(temp.effectiveWindow > 0)
                        	        {
                        	                temp.effectiveWindow--;
                        	        }
					else
					{
						break;
					}
                        	}
				temp.rcvdBuff[j] = '\0';
				temp.lastRcvd = j - 1;
                        	if(temp.effectiveWindow == 0)
                        	{
                        	        temp.nextExpected = 0;
                        	}
                        	else
                        	{
                        	        temp.nextExpected = j;
                        	}
				if(flag == 11 && stringDone == TRUE)
				{
					//check if whole message is sent, then mass send it to clients
					temp.flag = 11;
					i = 0;
					writing = TRUE;
					printf("username is:\n");
					for(i = 0; i < 10; i++)
					{
						//printf("%c",temp.username[i]);
					}
					printf("\n%s\n", temp.username);
					printf("rcvdBuff is:\n%s\n",temp.rcvdBuff);
					i=0;
					while(writing)
					{
						if(temp.username[i] == '\r')
						{
							sendUser[i] = ':';
						}
						else if(temp.username[i] == '\n')
						{
							sendUser[i] = ' ';
							writing = FALSE;
						}
						else
						{
							//printf("%c",temp.username[i]);
							sendUser[i] = temp.username[i];
						}
						i++;
					}
					writing = TRUE;
					for(j = 0; j < 6; j++)
					{
						//sendThis[i] = temp.rcvdBuff[j];
						//i++;
						printf("%c\n", temp.rcvdBuff[j]);
					}
					j = 0;
					while(writing)
					{
						if(temp.rcvdBuff[j] == '\n')
						{
							sendMsg[j] = temp.rcvdBuff[j];
							j++;
							i++;
							writing = FALSE;
						}
						else if(temp.rcvdBuff[j] == '\0')
						{
							j++;
						}
						else
						{
							sendMsg[j] = temp.rcvdBuff[j];
							j++;
							i++;
						}
					}
					printf("sendThis is:\n");
					for(i = 0; i < 128; i++)
					{
						//printf("%c",sendThis[i]);
					}
					printf("%s", sendMsg);
					printf("\n");
					for(i = 0; i < sockLen; i++)
					{
						printf("sockiteration\n");
						temp2 = call Sockets.get(i);
						printf("sock: %d\n", temp2.dest.port);
						for(j = 0; j < call Confirmed.size(); j++)
						{
							printf("confimedloop\n");
							destination = call Confirmed.get(j);
							printf("confirm: %d\n", destination.Dest);
							if(9 == destination.Dest)
							{
								printf("sending sendThis\n");
								next = destination.Next;
								send.src = TOS_NODE_ID;
								send.dest = temp2.dest.addr;
								send.protocol = 10;
								send.seq = 0;
								send.TTL = MAX_TTL;
								memcpy(send.payload, &sendUser, (char*) sizeof(sendUser));
								call Sender.send(send,next);
								return 0;
								memcpy(send.payload, &sendMsg, (char*) sizeof(sendMsg));
								call Sender.send(send,next);
							}
						}
					}
				}
				else if(flag == 13)
				{
					//check if whole message is sent, then send to specific user
				}
				/*else //printing the whole rcvdBuff
				{
					while(temp.rcvdBuff[i] != '\0')
					{
						printf("%d ", temp.rcvdBuff[i]);
						temp.sendBuff[i] = temp.rcvdBuff[i];
						temp.effectiveWindow++;
						i++;
					}
					temp.effectiveWindow = 128;
					temp.nextExpected = 0;
					for(i = 0; i < 128; i++)
					{
						temp.rcvdBuff[i] = '\0';
					}
					printf("\n");
				}*/
				//pushing stuff
	                        while(!call Sockets.isEmpty())
	                        {
	                                temp2 = call Sockets.front();
	                                if(temp.fd != temp2.fd)
	                                {
	                                        call TempSockets.pushfront(call Sockets.front());
	                                }
        	                        else
                	                {
					        call TempSockets.pushfront(temp);
        	                        }
                	                call Sockets.popfront();
                        	}
                        	while(!call TempSockets.isEmpty())
                        	{
                                	call Sockets.pushfront(call TempSockets.front());
                                	call TempSockets.popfront();
                        	}
                        	return buffcount;
			}
                }
        }

   /**
    * Attempts a connection to an address.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are attempting a connection with. 
    * @param
    *    socket_addr_t *addr: the destination address and port where
    *       you will atempt a connection.
    * @side Client
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a connection with the fd passed, else return FAIL.
    */
   command error_t Transport.connect(socket_t fd, socket_addr_t * addr) {
		pack syn;
		error_t success;
		bool sent;
		socket_store_t temp, temp2;
		uint16_t next;
		uint16_t i;
		LinkState destination;
		syn.dest = addr->addr;
		syn.src = TOS_NODE_ID;
		//dbg(TRANSPORT_CHANNEL, "TOS_NODE_ID = %d\n", TOS_NODE_ID);
		syn.seq = 1;
		syn.TTL = MAX_TTL;
		syn.protocol = 4;
		temp = call Sockets.get(fd);
		temp.flag = 1;
		temp.dest.port = addr->port;
		temp.dest.addr = addr->addr;

		while(!call Sockets.isEmpty())
		{
			temp2 = call Sockets.front();
			if(temp.fd == temp2.fd)
			{
				call TempSockets.pushfront(temp);
			}
			else
			{
				call TempSockets.pushfront(temp2);
			}
			call Sockets.popfront();
		}
		while(!call TempSockets.isEmpty())
		{
			call Sockets.pushfront(call TempSockets.front());
			call TempSockets.popfront();
		}

		memcpy(syn.payload, &temp, (uint8_t) sizeof(temp));
		
		for (i = 0; i < call Confirmed.size(); i++) {
			destination = call Confirmed.get(i);
			if (syn.dest == destination.Dest) {
				next = destination.Next;
				sent = TRUE;
			}
		}
		
		call Sender.send(syn, next);
		if (sent == TRUE)
			return success = SUCCESS;
		else
			return success = FAIL;
	}

	command error_t Transport.connectUser(socket_t fd, socket_addr_t * addr) {
		pack syn;
		error_t success;
		bool sent;
		socket_store_t temp, temp2;
		uint16_t next;
		uint16_t i;
		LinkState destination;
		syn.dest = addr->addr;
		syn.src = TOS_NODE_ID;
		//dbg(TRANSPORT_CHANNEL, "TOS_NODE_ID = %d\n", TOS_NODE_ID);
		syn.seq = 1;
		syn.TTL = MAX_TTL;
		syn.protocol = 4;
		temp = call Sockets.get(fd);
		temp.flag = 7;
		temp.dest.port = addr->port;
		temp.dest.addr = addr->addr;

		while(!call Sockets.isEmpty())
		{
			temp2 = call Sockets.front();
			if(temp.fd == temp2.fd)
			{
				call TempSockets.pushfront(temp);
			}
			else
			{
				call TempSockets.pushfront(temp2);
			}
			call Sockets.popfront();
		}
		while(!call TempSockets.isEmpty())
		{
			call Sockets.pushfront(call TempSockets.front());
			call TempSockets.popfront();
		}

		memcpy(syn.payload, &temp, (uint8_t) sizeof(temp));
		
		for (i = 0; i < call Confirmed.size(); i++) {
			destination = call Confirmed.get(i);
			if (syn.dest == destination.Dest) {
				next = destination.Next;
				sent = TRUE;
			}
		}
		
		call Sender.send(syn, next);
		if (sent == TRUE)
			return success = SUCCESS;
		else
			return success = FAIL;
	}

   /**
    * Closes the socket.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are closing. 
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
	command error_t Transport.close(socket_t fd)
	{
		socket_store_t temp;
		uint16_t i, at;
		error_t success;
		bool able = FALSE;
		while(!call Sockets.isEmpty())
		{
			temp = call Sockets.front();
			call Sockets.popfront();
			if(temp.fd == fd)
			{
				temp.state = CLOSED;
				able = TRUE;
			}
			call TempSockets.pushfront(temp);
		}
		while(!call TempSockets.isEmpty())
		{
			call Sockets.pushfront(call TempSockets.front());
			call TempSockets.popfront();
		}
		if(able == TRUE)
		{
			return success = SUCCESS;
		}
		else
		{
			return success = FAIL;
		}
	}

   /**
    * A hard close, which is not graceful. This portion is optional.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing. 
    * @side Client/Server
    * @return socket_t - returns SUCCESS if you are able to attempt
    *    a closure with the fd passed, else return FAIL.
    */
   command error_t Transport.release(socket_t fd) {}

   /**
    * Listen to the socket and wait for a connection.
    * @param
    *    socket_t fd: file descriptor that is associated with the socket
    *       that you are hard closing. 
    * @side Server
    * @return error_t - returns SUCCESS if you are able change the state 
    *   to listen else FAIL.
    */
	command error_t Transport.listen(socket_t fd)
	{
		socket_store_t temp;
		enum socket_state tempState;
		error_t success;
		bool found = FALSE;
		while (!call Sockets.isEmpty()) {
			temp = call Sockets.front();
			call Sockets.popfront();
			if (temp.fd == fd && !found) {
				tempState = LISTEN;
				temp.state = tempState;
				found = TRUE;
				//dbg(TRANSPORT_CHANNEL, "fd found, changing state to %d\n", temp.state);
				call TempSockets.pushfront(temp);
			}
			else {
				call TempSockets.pushfront(temp);
			}
		}
		while (!call TempSockets.isEmpty()) {
			call Sockets.pushfront(call TempSockets.front());
			call TempSockets.popfront();
		}
		if (found == TRUE)
			return success = SUCCESS;
		else
			return success = FAIL;
	}
}
