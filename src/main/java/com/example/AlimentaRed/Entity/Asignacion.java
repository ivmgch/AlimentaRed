package com.example.AlimentaRed.Entity;


import jakarta.persistence.*;
import lombok.Data;

@Data
@Entity
@Table(name = "asignacion")

public class Asignacion {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long idAsignacion;

    @OneToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "solicitud_id", unique = true)
    private Solicitud solicitud;

    @Column(nullable = false)
    private int cantidadAsignada;
}
