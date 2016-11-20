# L Game DQN

Implementation of the L Game, using Deep-Q Learning for training the AI player. Using variable size batch updates to accelerate training by mitigating loss of the rare reward signal.

Trained agent (AI) vs. random player:
https://youtu.be/9MGdRd4abiw

Since there are no draws in L-Game, games between 2 agents can go on for a very long time, unless we consider a draw if no winner has emerged after a set number of moves. In this case the draw rate between 2 trained agents is 100% within any reasonable amount of moves.




