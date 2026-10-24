package com.example.AlimentaRed.Entity;

import jakarta.persistence.*;
import lombok.Data;

@Data
@Entity
@Table(name = "incidencia")

public class Incidencia {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long idIncidencia;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "lote_id")
    private Lote lote;

    @Column(nullable = false, length = 500)
    private String detalles;
}
