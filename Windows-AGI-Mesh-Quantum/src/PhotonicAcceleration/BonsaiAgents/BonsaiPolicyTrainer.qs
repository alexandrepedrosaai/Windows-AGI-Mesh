namespace WindowsAGIMesh.Bonsai {

    operation BonsaiPolicyUpdate(state : Double, reward : Double) : Double {
        // Simplified RL policy update
        return state + reward * 0.1;
    }

    operation TrainBonsaiAgent(initial : Double, steps : Int) : Double {
        mutable policy = initial;

        for step in 1..steps {
            let reward = 0.05 * IntAsDouble(step);
            set policy = BonsaiPolicyUpdate(policy, reward);
        }

        return policy;
    }
}
