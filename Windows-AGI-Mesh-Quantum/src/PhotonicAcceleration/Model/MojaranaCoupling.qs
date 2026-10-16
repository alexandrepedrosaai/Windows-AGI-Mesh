operation MajoranaCoupling(gamma1 : Double, gamma2 : Double, distance : Double) : Double {
    let overlap = Exp(-distance * 10.0);
    return Abs(gamma1 - gamma2)  overlap  0.0000001;
}

operation SimulateMajoranaQubit(state : Double) : Double {
    let coupling = MajoranaCoupling(state, 0.5, 0.02);
    return state - coupling + 0.0000000001 * state;
}
